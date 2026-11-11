import AppKit

// MARK: - Models (decoded from the injected ExamBridge.js)

struct ExamChoice: Decodable {
    let letter: String
    let text: String
}

struct ExamSelect: Decodable {
    let label: String
    let options: [String]
}

struct ExamGap: Decodable {
    let type: String
    let options: [String]?
}

struct ExamQuestion: Decodable {
    let index: Int
    let kind: String
    let text: String
    let hasImage: Bool
    let choices: [ExamChoice]
    let selects: [ExamSelect]
    let orderItems: [String]
    let gaps: [ExamGap]
    let dropZones: Int
    let dragItems: [String]
    let units: [String]?
    let rect: [Double]?
}

struct ExamPage: Decodable {
    let error: String?
    let url: String?
    let title: String?
    let questions: [ExamQuestion]?
    let fingerprint: String?
}

struct ExamApplyResult: Decodable {
    let index: Int
    let filled: Bool
    let error: String?
}

struct ExamApplyResponse: Decodable {
    let error: String?
    let applied: Bool?
    let results: [ExamApplyResult]?
}

struct ExamNavResponse: Decodable {
    let navigated: Bool
    let url: String?
    let fingerprint: String?
}

struct ExamBridgeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Bridge

/// Talks to the frontmost browser to read an exam page and fill in answers.
/// Two targets:
///  - Safe Exam Browser (WebKit) via its local loopback HTTP bridge (127.0.0.1:47611,
///    no TCC/Automation permission required).
///  - Any Chromium browser (Chrome/Brave/Edge) via `execute ... javascript`.
@MainActor
struct ExamBridge {
    enum TargetKind { case seb, chromium }

    let kind: TargetKind
    let bundleID: String
    let processID: pid_t
    let windowID: String?
    let tabID: String?
    let pageURL: String?

    static let sebBundleID = "org.safeexambrowser.SafeExamBrowser"
    static let sebBridgeURL = URL(string: "http://127.0.0.1:47611/eval")!

    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev",
        "com.google.Chrome.canary", "org.chromium.Chromium", "com.brave.Browser",
        "com.brave.Browser.beta", "com.microsoft.edgemac", "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary", "com.microsoft.edgemac.Beta",
    ]

    static func frontmost() throws -> ExamBridge? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return nil }

        if bundleID == sebBundleID {
            return ExamBridge(kind: .seb, bundleID: bundleID, processID: app.processIdentifier,
                              windowID: nil, tabID: nil, pageURL: nil)
        }

        if chromiumBundleIDs.contains(bundleID) {
            let result = try script(bundleID: bundleID, timeout: 5, commands:
                "if (count of windows) = 0 then return {}\n" +
                "return {(id of front window as text), (id of active tab of front window as text), URL of active tab of front window}")
            guard result.numberOfItems == 3,
                  let windowID = result.atIndex(1)?.stringValue, !windowID.isEmpty,
                  let tabID = result.atIndex(2)?.stringValue, !tabID.isEmpty,
                  let urlString = result.atIndex(3)?.stringValue, !urlString.isEmpty
            else { return nil }
            return ExamBridge(kind: .chromium, bundleID: bundleID, processID: app.processIdentifier,
                              windowID: windowID, tabID: tabID, pageURL: urlString)
        }

        return nil
    }

    func extract() async throws -> ExamPage {
        let js = try bridgeJavaScript("{\"action\":\"extract\"}")
        let raw = try await evaluate(js)
        AutoAnswerLog.log("extract raw: \(String(raw.prefix(500)))")
        guard let data = raw.data(using: .utf8),
              let page = try? JSONDecoder().decode(ExamPage.self, from: data) else {
            throw ExamBridgeError(message: "The browser returned an invalid response.")
        }
        return page
    }

    func apply(answers: String, fingerprint: String) async throws -> ExamApplyResponse {
        let request: [String: Any] = ["action": "apply", "fingerprint": fingerprint, "answers": answers]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        let raw = try await evaluate(try bridgeJavaScript(json))
        AutoAnswerLog.log("apply raw: \(String(raw.prefix(600)))")
        guard let data = raw.data(using: .utf8),
              let response = try? JSONDecoder().decode(ExamApplyResponse.self, from: data) else {
            throw ExamBridgeError(message: "The browser returned an invalid fill result.")
        }
        return response
    }

    /// Clicks Moodle's "Next" button (one-question-per-page navigation). Returns
    /// false when there is no next page (i.e. the last question or the summary page).
    func nextPage() async throws -> Bool {
        let json = "{\"action\":\"next\"}"
        let raw = try await evaluate(try bridgeJavaScript(json))
        guard let data = raw.data(using: .utf8),
              let response = try? JSONDecoder().decode(ExamNavResponse.self, from: data) else {
            throw ExamBridgeError(message: "The browser returned an invalid navigation result.")
        }
        guard response.navigated else { return false }
        // The click only *starts* an asynchronous navigation (the URL/fingerprint don't
        // change until the new page commits). Poll the page and report success once it
        // actually advances; return false if it never does (stuck or final "Next").
        for _ in 0..<6 {
            try await Task.sleep(nanoseconds: 700_000_000)
            let page = try await extract()
            if let before = response.fingerprint, let after = page.fingerprint, after != before {
                return true
            }
            if let before = response.url, let after = page.url, after != before {
                return true
            }
        }
        return false
    }

    // MARK: - JavaScript execution

    /// Builds the invocation `(<ExamBridge.js source>)(<json>)`.
    private func bridgeJavaScript(_ requestJSON: String) throws -> String {
        let bundleName = "BlindSpot_BlindSpot.bundle"
        let packagedBundle = Bundle.main.resourceURL?.appendingPathComponent(bundleName)
        let bundle = packagedBundle.flatMap(Bundle.init(url:)) ?? Bundle.module
        guard let resource = bundle.url(forResource: "ExamBridge", withExtension: "js") else {
            throw ExamBridgeError(message: "The exam browser adapter is missing. Reinstall BlindSpot.")
        }
        let source = try String(contentsOf: resource, encoding: .utf8)
        return "\(source)(\(requestJSON))"
    }

    private func evaluate(_ javascript: String) async throws -> String {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else {
            throw ExamBridgeError(message: "The active app changed. Return to your exam and try again.")
        }

        switch kind {
        case .seb:
            return try await evaluateInSEB(javascript)

        case .chromium:
            return try await evaluateInChromium(javascript)
        }
    }

    private func evaluateInSEB(_ javascript: String) async throws -> String {
        var req = URLRequest(url: Self.sebBridgeURL)
        req.httpMethod = "POST"
        req.httpBody = javascript.data(using: .utf8)
        req.timeoutInterval = 30
        req.setValue("BSBridge-7f3a9c2e", forHTTPHeaderField: "X-Bridge-Token")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let value = String(data: data, encoding: .utf8), !value.isEmpty else {
                throw ExamBridgeError(message: "Safe Exam Browser's bridge returned no result.")
            }
            return value
        } catch let e as ExamBridgeError {
            throw e
        } catch {
            AutoAnswerLog.log("SEB bridge error: \(error.localizedDescription)")
            throw ExamBridgeError(message: "Safe Exam Browser's bridge did not respond. Make sure the exam is open in Safe Exam Browser.")
        }
    }

    private func evaluateInChromium(_ javascript: String) async throws -> String {
        guard let windowID, let tabID else {
            throw ExamBridgeError(message: "The browser tab is no longer available.")
        }
        let escaped = Self.escapeAppleScript(javascript)
        let eWindow = Self.escapeAppleScript(windowID)
        let eTab = Self.escapeAppleScript(tabID)
        let commands =
            "if (count of windows) = 0 then error \"The browser window closed.\"\n" +
            "if (id of front window as text) is not \"\(eWindow)\" then error \"The browser window changed.\"\n" +
            "if (id of active tab of front window as text) is not \"\(eTab)\" then error \"The active tab changed.\"\n" +
            "return execute active tab of front window javascript \"\(escaped)\""
        // NSAppleScript.executeAndReturnError blocks; run it off the main thread so the
        // UI stays responsive during the (up to 30s) browser call. Page-change detection
        // is already covered by the JS fingerprint on apply, not by URL equality.
        let value = try await Task.detached {
            try Self.script(bundleID: bundleID, timeout: 30, commands: commands).stringValue
        }.value
        guard let value else {
            throw ExamBridgeError(message: "The browser returned no result.")
        }
        return value
    }

    // MARK: - AppleScript plumbing (Chromium only)

    private static func escapeAppleScript(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private nonisolated static func script(bundleID: String, timeout: Int, commands: String) throws -> NSAppleEventDescriptor {
        let source = "with timeout of \(timeout) seconds\ntell application id \"\(bundleID)\"\n\(commands)\nend tell\nend timeout"
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw ExamBridgeError(message: "Could not prepare browser automation.")
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let detail = error[NSAppleScript.errorMessage] as? String ?? "Browser automation failed."
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            AutoAnswerLog.log("AppleScript error (code \(code ?? 0)): \(detail)")
            if code == -1743 {
                throw ExamBridgeError(message: "\(detail)\n\nAllow BlindSpot in System Settings > Privacy & Security > Automation.")
            }
            throw ExamBridgeError(message: detail)
        }
        return result
    }
}
