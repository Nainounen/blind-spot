import AppKit

struct BrowserQuestion: Decodable {
    let title: String
    let description: String
    let kind: String
    let options: [String]
    let details: String
    let answerFormat: String
    let maxSteps: Int
    let fingerprint: String
    let state: String
}

struct BrowserBridgeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
struct ChromiumQuestionBridge {
    let bundleID: String
    let processID: pid_t
    let windowID: Int
    let tabID: Int
    let pageURL: String

    private static let supportedBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.brave.Browser", "com.microsoft.edgemac"
    ]

    static func frontmostClasstime() throws -> ChromiumQuestionBridge? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier, supportedBrowsers.contains(bundleID) else { return nil }
        let result = try script(bundleID: bundleID, commands: "if (count of windows) = 0 then return {}\nreturn {id of front window, id of active tab of front window, URL of active tab of front window}")
        guard result.numberOfItems == 3,
              let urlString = result.atIndex(3)?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "https", let host = url.host,
              host == "classtime.com" || host.hasSuffix(".classtime.com") else { return nil }
        return ChromiumQuestionBridge(bundleID: bundleID, processID: app.processIdentifier,
                                      windowID: Int(result.atIndex(1)!.int32Value),
                                      tabID: Int(result.atIndex(2)!.int32Value), pageURL: urlString)
    }

    func extract() throws -> BrowserQuestion {
        let data = try execute(["action": "extract"])
        return try JSONDecoder().decode(BrowserQuestion.self, from: data)
    }

    func apply(_ response: String, to question: BrowserQuestion) async throws {
        guard let responseData = response.data(using: .utf8),
              let answer = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw BrowserBridgeError(message: "The AI did not return a valid answer. Nothing was changed.")
        }
        var expectedState = question.state
        var phase = ""
        // Each pass changes at most one control, then lets the browser commit its update.
        for _ in 0..<min(max(question.maxSteps, 4), 256) {
            try Task.checkCancellation()
            let data = try execute(["action": "apply", "fingerprint": question.fingerprint,
                                    "state": expectedState, "answer": answer, "phase": phase])
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BrowserBridgeError(message: "The browser returned an invalid fill result.")
            }
            if result["applied"] as? Bool == true { return }
            guard result["pending"] as? Bool == true, let state = result["state"] as? String else {
                throw BrowserBridgeError(message: "The browser could not confirm the answer.")
            }
            expectedState = state
            phase = result["phase"] as? String ?? ""
            try await Task.sleep(for: .milliseconds(150))
        }
        throw BrowserBridgeError(message: "Classtime did not retain the answer. Check the question before submitting.")
    }

    private func execute(_ request: [String: Any]) throws -> Data {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else {
            throw BrowserBridgeError(message: "The active app changed. Return to your question and try again.")
        }
        let bundleName = "BlindSpot_BlindSpot.bundle"
        let packagedBundle = Bundle.main.resourceURL?.appendingPathComponent(bundleName)
        let bundle = packagedBundle.flatMap(Bundle.init(url:)) ?? Bundle.module
        guard let resource = bundle.url(forResource: "ClasstimeBridge", withExtension: "js") else {
            throw BrowserBridgeError(message: "The Classtime browser adapter is missing. Reinstall BlindSpot.")
        }
        let source = try String(contentsOf: resource, encoding: .utf8)
        let json = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        let javascript = "\(source)(\(json))"
        let escaped = javascript.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
        let escapedURL = pageURL.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
        let commands = "if (count of windows) = 0 then error \"The browser window closed.\"\n" +
            "if id of front window is not \(windowID) then error \"The browser window changed.\"\n" +
            "if id of active tab of front window is not \(tabID) then error \"The active tab changed.\"\n" +
            "if URL of active tab of front window is not \"\(escapedURL)\" then error \"The page changed.\"\n" +
            "return execute active tab of front window javascript \"\(escaped)\""
        let result = try Self.script(bundleID: bundleID, commands: commands)
        guard let value = result.stringValue, let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrowserBridgeError(message: "The browser returned an invalid response.")
        }
        if let message = object["error"] as? String { throw BrowserBridgeError(message: message) }
        return data
    }

    private static func script(bundleID: String, commands: String) throws -> NSAppleEventDescriptor {
        let source = "with timeout of 5 seconds\ntell application id \"\(bundleID)\"\n\(commands)\nend tell\nend timeout"
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw BrowserBridgeError(message: "Could not prepare browser automation.")
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let detail = error[NSAppleScript.errorMessage] as? String ?? "Browser automation failed."
            throw BrowserBridgeError(message: "\(detail)\n\nAllow BlindSpot in System Settings > Privacy & Security > Automation. In your browser, enable View > Developer > Allow JavaScript from Apple Events.")
        }
        return result
    }
}
