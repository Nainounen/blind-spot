import Foundation

enum Config {
    static var apiKey: String {
        // 1. Environment variable (preferred when running from terminal)
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return key
        }
        // 2. Config file at ~/.config/blind-spot/api-key
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blind-spot/api-key")
        if let key = try? String(contentsOf: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return key
        }
        return ""
    }

    static let model = "gpt-4o"
    static let maxTokens = 1024

    static var systemPrompt: String? {
        let name = ProcessInfo.processInfo.environment["BLIND_SPOT_PROMPT"] ?? ""
        guard !name.isEmpty else { return nil }
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blind-spot/prompts/\(name).txt")
        return try? String(contentsOf: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
