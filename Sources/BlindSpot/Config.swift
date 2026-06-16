import Foundation

enum Provider: String, CaseIterable, Codable {
    case openai
    case anthropic
    case gemini
    case deepseek
    case grok
    case openrouter
    case ollama

    var displayName: String {
        switch self {
        case .openai:     return "OpenAI"
        case .anthropic:  return "Anthropic"
        case .gemini:     return "Gemini"
        case .deepseek:   return "DeepSeek"
        case .grok:       return "Grok"
        case .openrouter: return "OpenRouter"
        case .ollama:     return "Ollama"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai:     return "gpt-4o"
        case .anthropic:  return "claude-sonnet-4-5"
        case .gemini:     return "gemini-2.5-flash"
        case .deepseek:   return "deepseek-v4-flash"
        case .grok:       return "grok-3"
        case .openrouter: return "openai/gpt-4o"
        case .ollama:     return "llama3.2"
        }
    }

    var requiresKey: Bool { self != .ollama }

    var supportsThinking: Bool {
        switch self {
        case .openai, .anthropic, .deepseek, .grok, .openrouter: return true
        case .gemini, .ollama: return false
        }
    }

    var thinkingDescription: String {
        switch self {
        case .openai, .grok, .openrouter:
            return "Reasoning models (o3, o4-mini, grok-3-mini…) think before answering. Has no effect on non-reasoning models."
        case .anthropic:
            return "Claude thinks before answering using adaptive thinking. Temperature still applies."
        case .deepseek:
            return "DeepSeek-v4-Pro thinking mode. Only applies to the deepseek-v4-pro model. Temperature is ignored."
        default:
            return ""
        }
    }

    var signupURL: String? {
        switch self {
        case .openai:     return "https://platform.openai.com/api-keys"
        case .anthropic:  return "https://console.anthropic.com/settings/keys"
        case .gemini:     return "https://aistudio.google.com/app/apikey"
        case .deepseek:   return "https://platform.deepseek.com/api_keys"
        case .grok:       return "https://console.x.ai"
        case .openrouter: return "https://openrouter.ai/keys"
        case .ollama:     return nil
        }
    }

    /// Asset catalog image name for the provider logo SVG.
    var logoImageName: String { "provider-\(rawValue)" }

    /// SF Symbol used as a fallback when the real logo SVG hasn't been added yet.
    var fallbackIcon: String {
        switch self {
        case .openai:     return "sparkle"
        case .anthropic:  return "brain.head.profile"
        case .gemini:     return "sparkles"
        case .deepseek:   return "cpu"
        case .grok:       return "bolt"
        case .openrouter: return "arrow.triangle.branch"
        case .ollama:     return "laptopcomputer"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .openai:     return ["gpt-4o", "gpt-4o-mini", "o3", "o4-mini"]
        case .anthropic:  return ["claude-sonnet-4-5", "claude-opus-4-8", "claude-haiku-4-5-20251001"]
        case .gemini:     return ["gemini-2.5-flash", "gemini-2.5-pro"]
        case .deepseek:   return ["deepseek-v4-flash", "deepseek-v4-pro", "deepseek-reasoner"]
        case .grok:       return ["grok-3", "grok-3-mini"]
        case .openrouter: return ["openai/gpt-4o", "anthropic/claude-sonnet-4-5", "deepseek/deepseek-v4-flash", "google/gemini-2.5-flash", "meta-llama/llama-3.1-8b-instruct:free"]
        case .ollama:     return []
        }
    }
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
        if prov == .deepseek, let k = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !k.isEmpty { return k }
        if prov == .grok {
            for name in ["XAI_API_KEY", "GROK_API_KEY"] {
                if let k = ProcessInfo.processInfo.environment[name], !k.isEmpty { return k }
            }
        }
        if prov == .openrouter, let k = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !k.isEmpty { return k }
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

    static var maxTokens: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxTokens")
        return stored > 0 ? stored : 4096
    }

    static var systemPrompt: String? {
        // 1. Named prompt selected via env var (overrides the global prompt)
        let name = ProcessInfo.processInfo.environment["BLIND_SPOT_PROMPT"] ?? ""
        if !name.isEmpty {
            let path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/blind-spot/prompts/\(name).txt")
            if let p = try? String(contentsOf: path, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                return p
            }
        }
        // 2. Global system prompt set in Settings
        let globalPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blind-spot/system-prompt.txt")
        if let p = try? String(contentsOf: globalPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return p
        }
        return nil
    }
}
