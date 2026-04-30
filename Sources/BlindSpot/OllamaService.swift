import Foundation

/// Talks to the local Ollama server (http://localhost:11434) to discover
/// installed models. Used to keep BlindSpot from pointing at a model the
/// user hasn't actually pulled.
enum OllamaService {
    struct Model: Decodable, Hashable {
        let name: String
        let size: Int64
        let details: Details?

        struct Details: Decodable, Hashable {
            let parameter_size: String?
            let family: String?
        }
    }

    private struct ListResponse: Decodable {
        let models: [Model]
    }

    /// GET /api/tags. Returns nil when the server is unreachable or returns
    /// a non-200 status. Treat nil as "Ollama not running".
    static func listInstalledModels() async -> [Model]? {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.0
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(ListResponse.self, from: data).models
        } catch {
            return nil
        }
    }

    /// Picks the "best" installed model by parameter size (e.g. `7B` > `3.2B`),
    /// falling back to on-disk byte size. Returns nil for an empty input.
    static func bestInstalledModel(in models: [Model]) -> Model? {
        models.max { lhs, rhs in
            score(for: lhs) < score(for: rhs)
        }
    }

    private static func score(for model: Model) -> Double {
        if let p = parameterCount(model.details?.parameter_size) {
            return p
        }
        // No parameter_size string — use disk size in GB as a fallback.
        return Double(model.size) / 1_000_000_000.0
    }

    /// Parses Ollama's parameter_size strings like "7B", "3.2B", "70B" or
    /// "350M" into a comparable Double (in billions of parameters).
    private static func parameterCount(_ raw: String?) -> Double? {
        guard let s = raw?.uppercased().trimmingCharacters(in: .whitespaces),
              let last = s.last else { return nil }
        let multiplier: Double
        let body: String
        switch last {
        case "B": multiplier = 1.0;     body = String(s.dropLast())
        case "M": multiplier = 0.001;   body = String(s.dropLast())
        case "K": multiplier = 0.000001; body = String(s.dropLast())
        default:  multiplier = 1.0;     body = s
        }
        return Double(body).map { $0 * multiplier }
    }
}
