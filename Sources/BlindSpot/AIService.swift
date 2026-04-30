import Foundation

enum AIService {
    enum Error: Swift.Error, LocalizedError {
        case missingAPIKey
        case httpError(Int, String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "No API key — set OPENAI_API_KEY or write it to ~/.config/blind-spot/api-key"
            case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
            case .emptyResponse: return "Empty response from API"
            }
        }
    }

    static func query(_ text: String) async throws -> AsyncThrowingStream<String, Swift.Error> {
        let key = Config.apiKey
        guard !key.isEmpty else { throw Error.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var messages: [[String: String]] = []
        if let prompt = Config.systemPrompt {
            messages.append(["role": "system", "content": prompt])
        }
        messages.append(["role": "user", "content": text])

        let body: [String: Any] = [
            "model": Config.model,
            "max_tokens": Config.maxTokens,
            "stream": true,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (stream, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Error.emptyResponse }
        guard http.statusCode == 200 else {
            var body = ""
            for try await line in stream.lines { body += line }
            throw Error.httpError(http.statusCode, body)
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in stream.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        guard json != "[DONE]" else { break }
                        guard let data = json.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let chunk = delta["content"] as? String
                        else { continue }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
