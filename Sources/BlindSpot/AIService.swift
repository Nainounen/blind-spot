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

    static func query(
        _ messages: [ConversationMessage],
        profile: AIProfile
    ) async throws -> AsyncThrowingStream<String, Swift.Error> {
        switch profile.provider {
        case .openai:
            return try await queryOpenAICompatible(
                messages, profile: profile,
                endpoint: "https://api.openai.com/v1/chat/completions"
            )
        case .deepseek:
            return try await queryOpenAICompatible(
                messages, profile: profile,
                endpoint: "https://api.deepseek.com/v1/chat/completions"
            )
        case .grok:
            return try await queryOpenAICompatible(
                messages, profile: profile,
                endpoint: "https://api.x.ai/v1/chat/completions"
            )
        case .openrouter:
            return try await queryOpenAICompatible(
                messages, profile: profile,
                endpoint: "https://openrouter.ai/api/v1/chat/completions",
                extraHeaders: [
                    "HTTP-Referer": "https://github.com/unveroleone/blind-spot",
                    "X-Title": "BlindSpot",
                ]
            )
        case .anthropic: return try await queryAnthropic(messages, profile: profile)
        case .gemini:    return try await queryGemini(messages, profile: profile)
        case .ollama:    return try await queryOllama(messages, profile: profile)
        }
    }

    // MARK: - OpenAI-compatible (SSE: choices[0].delta.content)

    private static func queryOpenAICompatible(
        _ messages: [ConversationMessage],
        profile: AIProfile,
        endpoint: String,
        extraHeaders: [String: String] = [:]
    ) async throws -> AsyncThrowingStream<String, Swift.Error> {
        let key = apiKey(for: profile.provider)
        guard !key.isEmpty else { throw Error.missingAPIKey(profile.provider) }

        let apiMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (header, value) in extraHeaders {
            req.setValue(value, forHTTPHeaderField: header)
        }
        var body: [String: Any] = [
            "model": profile.model,
            "max_tokens": profile.maxOutputTokens,
            "stream": true,
            "messages": apiMessages,
        ]
        if profile.thinkingEnabled {
            body["reasoning_effort"] = profile.reasoningEffort.rawValue
            if profile.provider == .deepseek {
                body["thinking"] = ["type": "enabled"]
            }
        } else {
            body["temperature"] = profile.temperature
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
    // System prompt goes in a top-level "system" field, not inside messages.

    private static func queryAnthropic(
        _ messages: [ConversationMessage],
        profile: AIProfile
    ) async throws -> AsyncThrowingStream<String, Swift.Error> {
        let key = apiKey(for: .anthropic)
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
            "model": profile.model,
            "max_tokens": profile.maxOutputTokens,
            "stream": true,
            "messages": apiMessages,
        ]
        if let s = systemText { body["system"] = s }
        if profile.thinkingEnabled {
            body["thinking"] = ["type": "adaptive", "effort": profile.reasoningEffort.rawValue]
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
    // Assistant role maps to "model". System prompt goes in systemInstruction.

    private static func queryGemini(
        _ messages: [ConversationMessage],
        profile: AIProfile
    ) async throws -> AsyncThrowingStream<String, Swift.Error> {
        let key = apiKey(for: .gemini)
        guard !key.isEmpty else { throw Error.missingAPIKey(.gemini) }

        guard let escapedModel = profile.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
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
                ["role": m.role == .assistant ? "model" : "user",
                 "parts": [["text": m.content]]]
            }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": profile.maxOutputTokens,
                "temperature": profile.temperature,
            ],
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
        _ messages: [ConversationMessage],
        profile: AIProfile
    ) async throws -> AsyncThrowingStream<String, Swift.Error> {
        let apiMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        var req = URLRequest(url: URL(string: "http://localhost:11434/api/chat")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": profile.model,
            "stream": true,
            "messages": apiMessages,
            "options": ["temperature": profile.temperature],
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

    // Reads API key from env vars first, then falls back to the per-provider key file.
    // Called before the streaming Task starts, so no @MainActor isolation needed.
    static func apiKey(for provider: Provider) -> String {
        let env = ProcessInfo.processInfo.environment
        let envKey: String? = {
            switch provider {
            case .openai:     return env["BLIND_SPOT_API_KEY"] ?? env["OPENAI_API_KEY"]
            case .anthropic:  return env["ANTHROPIC_API_KEY"]
            case .gemini:     return env["GEMINI_API_KEY"] ?? env["GOOGLE_API_KEY"]
            case .deepseek:   return env["DEEPSEEK_API_KEY"]
            case .grok:       return env["XAI_API_KEY"] ?? env["GROK_API_KEY"]
            case .openrouter: return env["OPENROUTER_API_KEY"]
            case .ollama:     return nil
            }
        }()
        if let k = envKey, !k.isEmpty { return k }
        let keyFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blind-spot/keys/\(provider.rawValue)")
        return (try? String(contentsOf: keyFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
