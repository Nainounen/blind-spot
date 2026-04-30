import Foundation

enum AIService {
    enum Error: Swift.Error, LocalizedError {
        case missingAPIKey(Provider)
        case httpError(Int, String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey(let p):
                return "No API key for \(p.displayName) — run ./run.sh to set it up"
            case .httpError(let code, let msg):
                return "HTTP \(code): \(msg)"
            case .emptyResponse:
                return "Empty response from API"
            }
        }
    }

    static func query(_ text: String) async throws -> AsyncThrowingStream<String, Swift.Error> {
        switch Config.provider {
        case .openai:
            return try await queryOpenAICompatible(
                text,
                provider: .openai,
                endpoint: "https://api.openai.com/v1/chat/completions"
            )
        case .deepseek:
            // DeepSeek's API is OpenAI-compatible; same /v1/chat/completions
            // shape, same SSE format. Only the host differs.
            return try await queryOpenAICompatible(
                text,
                provider: .deepseek,
                endpoint: "https://api.deepseek.com/v1/chat/completions"
            )
        case .anthropic: return try await queryAnthropic(text)
        case .gemini:    return try await queryGemini(text)
        case .ollama:    return try await queryOllama(text)
        }
    }

    // MARK: - OpenAI-compatible  (SSE: choices[0].delta.content)
    //
    // Shared between OpenAI proper and any provider that exposes the same
    // /v1/chat/completions schema (DeepSeek, Together, Groq, Fireworks, etc.).

    private static func queryOpenAICompatible(
        _ text: String,
        provider: Provider,
        endpoint: String
    ) async throws -> AsyncThrowingStream<String, Swift.Error> {
        let key = Config.apiKey
        guard !key.isEmpty else { throw Error.missingAPIKey(provider) }

        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Config.model,
            "max_tokens": Config.maxTokens,
            "stream": true,
            "messages": buildMessages(text),
        ])

        let (stream, response) = try await URLSession.shared.bytes(for: req)
        try validateHTTP(response)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in stream.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        guard json != "[DONE]" else { break }
                        guard let data = json.data(using: .utf8),
                              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta   = choices.first?["delta"] as? [String: Any],
                              let chunk   = delta["content"] as? String
                        else { continue }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    // MARK: - Anthropic  (SSE: content_block_delta / delta.text)

    private static func queryAnthropic(_ text: String) async throws -> AsyncThrowingStream<String, Swift.Error> {
        let key = Config.apiKey
        guard !key.isEmpty else { throw Error.missingAPIKey(.anthropic) }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Anthropic takes system at the top level, not inside messages
        var body: [String: Any] = [
            "model": Config.model,
            "max_tokens": Config.maxTokens,
            "stream": true,
            "messages": [["role": "user", "content": text]],
        ]
        if let prompt = Config.systemPrompt { body["system"] = prompt }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (stream, response) = try await URLSession.shared.bytes(for: req)
        try validateHTTP(response)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in stream.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        guard let data = json.data(using: .utf8),
                              let obj   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type_ = obj["type"] as? String,
                              type_ == "content_block_delta",
                              let delta = obj["delta"] as? [String: Any],
                              let chunk = delta["text"] as? String
                        else { continue }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    // MARK: - Gemini  (SSE: candidates[0].content.parts[*].text)

    private static func queryGemini(_ text: String) async throws -> AsyncThrowingStream<String, Swift.Error> {
        let key = Config.apiKey
        guard !key.isEmpty else { throw Error.missingAPIKey(.gemini) }

        // Model name is sent in the URL path, key as a query parameter.
        guard let escapedModel = Config.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let escapedKey   = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escapedModel):streamGenerateContent?alt=sse&key=\(escapedKey)")
        else { throw Error.emptyResponse }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [["text": text]],
            ]],
            "generationConfig": [
                "maxOutputTokens": Config.maxTokens,
            ],
        ]
        if let prompt = Config.systemPrompt {
            body["systemInstruction"] = ["parts": [["text": prompt]]]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (stream, response) = try await URLSession.shared.bytes(for: req)
        try validateHTTP(response)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in stream.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        guard let data = json.data(using: .utf8),
                              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let candidates = obj["candidates"] as? [[String: Any]],
                              let content = candidates.first?["content"] as? [String: Any],
                              let parts   = content["parts"] as? [[String: Any]]
                        else { continue }
                        for part in parts {
                            if let chunk = part["text"] as? String, !chunk.isEmpty {
                                continuation.yield(chunk)
                            }
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    // MARK: - Ollama  (newline JSON: message.content)

    private static func queryOllama(_ text: String) async throws -> AsyncThrowingStream<String, Swift.Error> {
        var req = URLRequest(url: URL(string: "http://localhost:11434/api/chat")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Config.model,
            "stream": true,
            "messages": buildMessages(text),
        ])

        let (stream, response) = try await URLSession.shared.bytes(for: req)
        try validateHTTP(response)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in stream.lines {
                        guard !line.isEmpty,
                              let data    = line.data(using: .utf8),
                              let obj     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let message = obj["message"] as? [String: Any],
                              let chunk   = message["content"] as? String
                        else { continue }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    // MARK: - Shared helpers

    private static func buildMessages(_ text: String) -> [[String: String]] {
        var msgs: [[String: String]] = []
        if let prompt = Config.systemPrompt {
            msgs.append(["role": "system", "content": prompt])
        }
        msgs.append(["role": "user", "content": text])
        return msgs
    }

    private static func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw Error.emptyResponse }
        guard http.statusCode == 200 else {
            throw Error.httpError(
                http.statusCode,
                HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
    }
}
