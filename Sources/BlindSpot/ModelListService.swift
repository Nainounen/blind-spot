import Foundation

/// Fetches the live model list from a provider's /models endpoint so the
/// model picker never goes stale. Returns nil when the request fails.
enum ModelListService {
    static func fetch(_ provider: Provider) async -> [String]? {
        if provider == .ollama {
            return await OllamaService.listInstalledModels()?.map(\.name)
        }
        let key = AIService.apiKey(for: provider)
        if provider.requiresKey && key.isEmpty { return nil }

        let url: URL?
        switch provider {
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/models?limit=1000")
        case .gemini:
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000&key=\(k)")
        default:
            url = provider.openAIBaseURL.flatMap { URL(string: $0 + "/models") }
        }
        guard let url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        switch provider {
        case .anthropic:
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini:
            break
        default:
            if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        }

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let ids: [String]
        if provider == .gemini {
            ids = (obj["models"] as? [[String: Any]] ?? [])
                .filter { ($0["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true }
                .compactMap { ($0["name"] as? String)?.replacingOccurrences(of: "models/", with: "") }
        } else {
            ids = (obj["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        }
        return ids.filter { isChatModel($0, provider: provider) }.sorted()
    }

    // ponytail: substring blocklist for the mixed OpenAI/Gemini catalogs; extend when new non-chat families appear.
    private static func isChatModel(_ id: String, provider: Provider) -> Bool {
        guard provider == .openai || provider == .gemini else { return true }
        let blocked = ["embedding", "tts", "whisper", "audio", "realtime", "transcribe",
                       "image", "dall-e", "moderation", "search", "davinci", "babbage", "sora", "codex",
                       "lyria", "robotics", "computer-use", "deep-research", "antigravity", "banana", "customtools"]
        return !blocked.contains { id.contains($0) }
    }
}
