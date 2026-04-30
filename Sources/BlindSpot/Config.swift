import Foundation

enum Provider: String, CaseIterable {
    case openai
    case anthropic
    case gemini
    case ollama

    var displayName: String {
        switch self {
        case .openai:    return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini:    return "Gemini"
        case .ollama:    return "Ollama"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai:    return "gpt-4o"
        case .anthropic: return "claude-opus-4-5"
        case .gemini:    return "gemini-2.5-flash"
        case .ollama:    return "llama3.2"
        }
    }

    var requiresKey: Bool { self != .ollama }
}

// Config reads UserDefaults and files directly — no actor isolation needed.
// PreferencesStore writes to the same locations from the UI layer.
enum Config {
    // MARK: - Provider

    static var provider: Provider {
        if let v = ProcessInfo.processInfo.environment["BLIND_SPOT_PROVIDER"],
           let p = Provider(rawValue: v) { return p }
        let raw = UserDefaults.standard.string(forKey: "provider") ?? "openai"
        return Provider(rawValue: raw) ?? .openai
    }

    // MARK: - Model

    static var model: String {
        if let v = ProcessInfo.processInfo.environment["BLIND_SPOT_MODEL"], !v.isEmpty { return v }
        if let data = UserDefaults.standard.data(forKey: "modelOverrides"),
           let map  = try? JSONDecoder().decode([String: String].self, from: data),
           let m    = map[provider.rawValue], !m.isEmpty { return m }
        return provider.defaultModel
    }

    // MARK: - API Key

    static var apiKey: String {
        let prov = provider
        if let k = ProcessInfo.processInfo.environment["BLIND_SPOT_API_KEY"], !k.isEmpty { return k }
        if prov == .openai, let k = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !k.isEmpty { return k }
        if prov == .anthropic, let k = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !k.isEmpty { return k }
        if prov == .gemini {
            for name in ["GEMINI_API_KEY", "GOOGLE_API_KEY"] {
                if let k = ProcessInfo.processInfo.environment[name], !k.isEmpty { return k }
            }
        }
        // Per-provider key file (written by UI or run.sh)
        let keyFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blind-spot/keys/\(prov.rawValue)")
        if let k = try? String(contentsOf: keyFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty { return k }
        // Legacy single-file (openai only, backwards compat)
        if prov == .openai {
            let legacy = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/blind-spot/api-key")
            if let k = try? String(contentsOf: legacy, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty { return k }
        }
        return ""
    }

    // MARK: - Misc

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
