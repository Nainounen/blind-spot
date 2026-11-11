import Foundation

/// Debug log for the auto-answer flow. Appends timestamped lines to
/// ~/.config/blind-spot/logs/autoanswer.log so the full trace (detection,
/// extraction, prompt, AI response, apply result) survives a GUI app launch.
enum AutoAnswerLog {
    private static let logURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blind-spot/logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("autoanswer.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    // Serial queue confines the shared (non-Sendable) DateFormatter and all file
    // writes to a single thread, so concurrent callers — the hotkey tap, detached
    // AppleScript tasks, and the answer flow — can't race or interleave log lines.
    private static let queue = DispatchQueue(label: "blindspot.autoanswer-log")

    static func log(_ line: String) {
        queue.async {
            let entry = "[\(formatter.string(from: Date()))] \(line)\n"
            print("[AutoAnswerLog] \(line)")
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: Data(entry.utf8))
                try? handle.close()
            } else {
                try? entry.data(using: .utf8)?.write(to: logURL)
            }
        }
    }
}
