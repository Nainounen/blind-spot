import Foundation

enum AIService {
    enum Error: Swift.Error, LocalizedError {
        case missingAPIKey(Provider)
        case httpError(Int, String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey(let p):
                return "No API key for \(p.displayName) — open Settings to add one"
            case .httpError(let code, let msg):
                return "HTTP \(code): \(msg)"
            case .emptyResponse:
                return "Empty response from API"
            }
        }
    }

    static func query(_ messages: [ConversationMessage]) async throws -> AsyncThrowingStream<String, Swift.Error> {
        switch Config.provider {
        case .openai:
            return try await queryOpenAICompatible(
                messages,
                provider: .openai,
                endpoint: "https://api.openai.com/v1/chat/completions"
            )
        case .deepseek:
            return try await queryOpenAICompatible(
                messages,
                provider: .deepseek,
                endpoint: "https://api.deepseek.com/v1/chat/completions"
            )
        case .grok:
            return try await queryOpenAICompatible(
                messages,
                provider: .grok,
                endpoint: "https://api.x.ai/v1/chat/completions"
            )
        case .anthropic: return try await queryAnthropic(messages)
        case .gemini:    return try await queryGemini(messages)
        case .ollama:    return try await queryOllama(messages)
        }
    }

    // MARK: - OpenAI-compatible (SSE: choices[0].delta.content)

    private static func queryOpenAICompatible(
        _ messages: [ConversationMessage],
        provider: Provider,
        endpoint: String
    ) async throws -> AsyncThrowingStream<String, Swift.Error> {
        let key = Config.apiKey
        guard !key.isEmpty else { throw Error.missingAPIKey(provider) }

        let apiMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Config.model,
            "max_tokens": Config.maxTokens,
            "stream": true,
            "messages": apiMessages,
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

    // MARK: - Anthropic (SSE: content_block_delta / delta.text)
    //
    // Anthropic requires: system at top-level, messages array must alternate
    // user/assistant starting with user. Filter out system from messages.

    private static func queryAnthropic(
        _ messages: [ConversationMessage]
    ) async throws -> AsyncThrowingStream<String, Swift.Error> {
        let key = Config.apiKey
        guard !key.isEmpty else { throw Error.missingAPIKey(.anthropic) }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemText = messages.first(where: { $0.role == .system })?.content
        let apiMessages = messages
            .filter { $0.role != .system }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        var body: [String: Any] = [
            "model": Config.model,
            "max_tokens": Config.maxTokens,
            "stream": true,
            "messages": apiMessages,
        ]
        if let s = systemText { body["system"] = s }
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

    // MARK: - Gemini (SSE: candidates[0].content.parts[*].text)
    //
    // Gemini uses "model" for the assistant role, not "assistant".
    // System prompt goes in systemInstruction, not in contents.

    private static func queryGemini(
        _ messages: [ConversationMessage]
    ) async throws -> AsyncThrowingStream<String, Swift.Error> {
        let key = Config.apiKey
        guard !key.isEmpty else { throw Error.missingAPIKey(.gemini) }

        guard let escapedModel = Config.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let escapedKey   = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escapedModel):streamGenerateContent?alt=sse&key=\(escapedKey)")
        else { throw Error.emptyResponse }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemText = messages.first(where: { $0.role == .system })?.content
        let contents: [[String: Any]] = messages
            .filter { $0.role != .system }
            .map { m in
                let role = m.role == .assistant ? "model" : "user"
                return ["role": role, "parts": [["text": m.content]]]
            }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": ["maxOutputTokens": Config.maxTokens],
        ]
        if let s = systemText {
            body["systemInstruction"] = ["parts": [["text": s]]]
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

    // MARK: - Ollama (newline-delimited JSON: message.content)

    private static func queryOllama(
        _ messages: [ConversationMessage]
    ) async throws -> AsyncThrowingStream<String, Swift.Error> {
        let apiMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        var req = URLRequest(url: URL(string: "http://localhost:11434/api/chat")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Config.model,
            "stream": true,
            "messages": apiMessages,
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

    // MARK: - Shared

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
