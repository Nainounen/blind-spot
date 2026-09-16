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
        // When images are present and a vision provider is configured, route the
        // request through that provider's API instead of the primary text provider.
        let hasImages = messages.contains { $0.image != nil }
        let routingProvider = (hasImages ? profile.visionProvider : nil) ?? profile.provider
        let routingModel: String = {
            guard hasImages else { return profile.model }
            if profile.visionProvider != nil, let vm = profile.visionModel { return vm }
            // Only deepseek-flash accepts images; pro/reasoner would 400.
            if routingProvider == .deepseek { return "deepseek-flash" }
            // Text model belongs to another provider, so fall back to this one's default.
            return routingProvider == profile.provider ? profile.model : routingProvider.defaultModel
        }()

        // Build an effective profile so provider-specific behavior (thinking,
        // model defaults, etc.) uses the routing provider, not the original one.
        let eff = AIProfile(
            id: profile.id,
            name: profile.name,
            provider: routingProvider,
            model: routingModel,
            visionModel: nil,        // Don't recurse
            visionProvider: nil,     // Don't recurse
            systemPrompt: profile.systemPrompt,
            maxOutputTokens: profile.maxOutputTokens,
            temperature: profile.temperature,
            thinkingEnabled: profile.thinkingEnabled,
            reasoningEffort: profile.reasoningEffort
        )

        switch routingProvider {
        case .openai, .deepseek, .grok, .local:
            return try await queryOpenAICompatible(
                messages, profile: eff,
                endpoint: routingProvider.openAIBaseURL! + "/chat/completions"
            )
        case .openrouter:
            return try await queryOpenAICompatible(
                messages, profile: eff,
                endpoint: routingProvider.openAIBaseURL! + "/chat/completions",
                extraHeaders: [
                    "HTTP-Referer": "https://github.com/unveroleone/blind-spot",
                    "X-Title": "BlindSpot",
                ]
            )
        case .anthropic: return try await queryAnthropic(messages, profile: eff)
        case .gemini:    return try await queryGemini(messages, profile: eff)
        case .ollama:    return try await queryOllama(messages, profile: eff)
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
        guard !key.isEmpty || !profile.provider.requiresKey else { throw Error.missingAPIKey(profile.provider) }

        let apiMessages: [[String: Any]] = messages.map {
            ["role": $0.role.rawValue, "content": openAIContent(for: $0)]
        }

        let hasImages = messages.contains { $0.image != nil }
        let effectiveModel = hasImages ? (profile.visionModel ?? profile.model) : profile.model

        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (header, value) in extraHeaders {
            req.setValue(value, forHTTPHeaderField: header)
        }
        var body: [String: Any] = [
            "model": effectiveModel,
            // OpenAI o-series rejects max_tokens; others only know max_tokens.
            profile.provider == .openai ? "max_completion_tokens" : "max_tokens": profile.maxOutputTokens,
            "stream": true,
            "messages": apiMessages,
        ]
        let effort = profile.reasoningEffort
        if profile.provider == .deepseek {
            // DeepSeek thinks by default, so "off" has to be sent explicitly.
            body["thinking"] = ["type": profile.thinkingEnabled && !hasImages ? "enabled" : "disabled"]
        }
        if profile.thinkingEnabled && !hasImages {
            if effort != .auto {
                switch (profile.provider, effort) {
                case (.deepseek, _): body["reasoning_effort"] = effort.rawValue  // server maps medium to high
                case (.grok, .max):  body["reasoning_effort"] = "xhigh"
                case (_, .max):      body["reasoning_effort"] = "high"
                default:             body["reasoning_effort"] = effort.rawValue
                }
            }
        } else if let t = profile.temperature, profile.provider != .openai || effectiveModel.hasPrefix("gpt-4") {
            // ponytail: GPT-5 and o-series reject custom temperature; prefix check until OpenAI exposes capabilities.
            body["temperature"] = t
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
        let apiMessages: [[String: Any]] = messages
            .filter { $0.role != .system }
            .map { ["role": $0.role.rawValue, "content": anthropicContent(for: $0)] }

        let hasImages = messages.contains { $0.image != nil }
        let effectiveModel = hasImages ? (profile.visionModel ?? profile.model) : profile.model

        var body: [String: Any] = [
            "model": effectiveModel,
            "max_tokens": profile.maxOutputTokens,
            "stream": true,
            "messages": apiMessages,
        ]
        if let s = systemText { body["system"] = s }
        if profile.thinkingEnabled && !hasImages {
            if anthropicUsesBudgetTokens(effectiveModel) {
                let budget = ["low": 2048, "high": 16384, "max": 32000][profile.reasoningEffort.rawValue] ?? 8192
                // budget_tokens must stay below max_tokens, so reserve it on top of the answer.
                body["thinking"] = ["type": "enabled", "budget_tokens": budget]
                body["max_tokens"] = profile.maxOutputTokens + budget
            } else {
                body["thinking"] = ["type": "adaptive"]
                if profile.reasoningEffort != .auto {
                    body["output_config"] = ["effort": profile.reasoningEffort.rawValue]
                }
            }
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

    // Pre-4.6 Claude models only take budget_tokens; 4.6+ use adaptive thinking.
    // ponytail: name-based check, switch to the Models API capabilities if IDs get irregular.
    private static func anthropicUsesBudgetTokens(_ model: String) -> Bool {
        ["claude-3", "-4-0", "-4-1", "-4-5", "sonnet-4-2", "opus-4-2"].contains { model.contains($0) }
            || model == "claude-sonnet-4" || model == "claude-opus-4"
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

        let hasImages = messages.contains { $0.image != nil }
        let effectiveModel = hasImages ? (profile.visionModel ?? profile.model) : profile.model

        guard let escapedModel = effectiveModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
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
                 "parts": geminiParts(for: m)]
            }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": profile.maxOutputTokens,
            ].merging(profile.temperature.map { ["temperature": $0] } ?? [:]) { $1 },
        ]
        if let s = systemText {
            body["systemInstruction"] = ["parts": [["text": s]]]
        }
        // Thinking off leaves the model default: several Gemini models can't disable it.
        if profile.thinkingEnabled && !hasImages && profile.reasoningEffort != .auto {
            let effort = profile.reasoningEffort == .max ? "high" : profile.reasoningEffort.rawValue
            var config = body["generationConfig"] as! [String: Any]
            if effectiveModel.contains("gemini-2") {
                config["thinkingConfig"] = ["thinkingBudget": ["low": 2048, "medium": 8192, "high": 24576][effort]!]
            } else {
                config["thinkingConfig"] = ["thinkingLevel": effort]
            }
            body["generationConfig"] = config
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
            "options": profile.temperature.map { ["temperature": $0] } ?? [:],
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
            case .local:      return env["LOCAL_API_KEY"]
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

    // MARK: - Multimodal content builders

    // OpenAI-compatible: content is a string for text-only, or an array for vision.
    private static func openAIContent(for msg: ConversationMessage) -> Any {
        guard let img = msg.image else { return msg.content }
        return [
            ["type": "text", "text": msg.content],
            ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(img.base64PNG)"]],
        ] as [[String: Any]]
    }

    // Anthropic: content is a string for text-only, or an array for vision.
    private static func anthropicContent(for msg: ConversationMessage) -> Any {
        guard let img = msg.image else { return msg.content }
        return [
            ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": img.base64PNG]],
            ["type": "text", "text": msg.content],
        ] as [[String: Any]]
    }

    // Gemini: parts array always; image as inline_data.
    private static func geminiParts(for msg: ConversationMessage) -> [[String: Any]] {
        guard let img = msg.image else { return [["text": msg.content]] }
        return [
            ["text": msg.content],
            ["inline_data": ["mime_type": "image/png", "data": img.base64PNG]],
        ]
    }
}
