import Foundation

enum Provider: String, CaseIterable {
    case openai
    case anthropic
    case ollama

    var displayName: String {
        switch self {
        case .openai:    return "OpenAI"
        case .anthropic: return "Anthropic"
        case .ollama:    return "Ollama (local)"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai:    return "gpt-4o"
        case .anthropic: return "claude-opus-4-5"
        case .ollama:    return "llama3.2"
        }
    }

    var requiresKey: Bool { self != .ollama }
}

enum Config {
    static var provider: Provider {
        let name = ProcessInfo.processInfo.environment["BLIND_SPOT_PROVIDER"] ?? "openai"
        return Provider(rawValue: name) ?? .openai
    }

    static var apiKey: String {
        let prov = provider
        // 1. Generic env var
        if let k = ProcessInfo.processInfo.environment["BLIND_SPOT_API_KEY"], !k.isEmpty { return k }
        // 2. Legacy OpenAI env var (backwards compat)
        if prov == .openai, let k = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !k.isEmpty { return k }
        // 3. Per-provider key file ~/.config/blind-spot/keys/<provider>
        let keysDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blind-spot/keys/\(prov.rawValue)")
        if let k = try? String(contentsOf: keysDir, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !k.isEmpty { return k }
        // 4. Legacy single api-key file (OpenAI only)
        if prov == .openai {
            let legacy = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/blind-spot/api-key")
            if let k = try? String(contentsOf: legacy, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
               !k.isEmpty { return k }
        }
        return ""
    }

    static var model: String {
        ProcessInfo.processInfo.environment["BLIND_SPOT_MODEL"] ?? provider.defaultModel
    }

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
