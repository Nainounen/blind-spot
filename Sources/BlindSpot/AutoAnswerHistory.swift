import Foundation
import CryptoKit

@MainActor
enum AutoAnswerHistory {
    static func record(sessionKey: String, title: String, profile: AIProfile, question: String, answer: String) {
        let store = ConversationStore.shared
        var conversation = store.conversations.first {
            $0.autoAnswerSessionKey == sessionKey && $0.profileId == profile.id
        } ?? Conversation(title: title, profileId: profile.id)
        conversation.autoAnswerSessionKey = sessionKey
        if conversation.messages.isEmpty {
            let instructions = profile.fullSystemPrompt
            if !instructions.isEmpty {
                conversation.messages.append(ConversationMessage(role: .system, content: instructions))
            }
        }
        conversation.messages.append(ConversationMessage(role: .user, content: question))
        conversation.messages.append(ConversationMessage(role: .assistant, content: answer))
        store.upsert(conversation)
    }
}

extension ChromiumQuestionBridge {
    var historySessionKey: String {
        let url = URL(string: pageURL)
        var path = url?.path ?? pageURL
        // Classtime's final colon suffix selects a question within the same participant session.
        if path.hasPrefix("/code/"), let suffix = path.range(of: ":", options: .backwards) {
            path = String(path[..<suffix.lowerBound])
        }
        let identity = [bundleID, String(processID), tabID, url?.host ?? "", path].joined(separator: "\n")
        // Do not persist the participant URL or its access token in chat metadata.
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var historyTitle: String {
        let parts = URL(string: pageURL)?.pathComponents ?? []
        if let code = parts.firstIndex(of: "code"), parts.indices.contains(code + 1) {
            return "Auto-Answer: Classtime \(parts[code + 1])"
        }
        return "Auto-Answer: Classtime"
    }
}

extension BrowserQuestion {
    private var historyDetails: [String: Any] {
        guard let data = details.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    var historyQuestion: String {
        var sections = [title, description].filter { !$0.isEmpty }
        if !options.isEmpty { sections.append(options.map { "- \($0)" }.joined(separator: "\n")) }
        let details = historyDetails
        if let passage = details["passage"] as? String { sections.append(passage) }
        if let items = details["items"] as? [String], options.isEmpty {
            sections.append(items.map { "- \($0)" }.joined(separator: "\n"))
        }
        if let categories = details["categories"] as? [String] {
            sections.append("Categories: " + categories.joined(separator: ", "))
        }
        if let groups = details["groups"] as? [[String]] {
            sections.append(groups.enumerated().map { "Gap \($0.offset + 1): " + $0.element.joined(separator: " / ") }.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    func historyAnswer(_ response: String) -> String {
        guard let data = response.data(using: .utf8),
              let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return response }
        let details = historyDetails
        func label(_ index: Int, in labels: [String]) -> String {
            labels.indices.contains(index) ? labels[index] : "Option \(index + 1)"
        }
        if let text = answer["text"] as? String { return text }
        if let indices = answer["indices"] as? [Int] {
            return indices.map { "- " + label($0, in: options) }.joined(separator: "\n")
        }
        if let order = answer["order"] as? [Int] {
            return order.enumerated().map { "\($0.offset + 1). " + label($0.element, in: options) }.joined(separator: "\n")
        }
        if let fills = answer["fills"] as? [String] {
            let gaps = details["gaps"] as? [Any] ?? []
            return fills.enumerated().map { index, value in
                let choices = gaps.indices.contains(index) ? gaps[index] as? [[String: Any]] : nil
                let text = choices?.first { $0["value"] as? String == value }?["text"] as? String ?? value
                return "Gap \(index + 1): \(text)"
            }.joined(separator: "\n")
        }
        if let assignments = answer["categories"] as? [[Int]] {
            let items = details["items"] as? [String] ?? []
            let categories = details["categories"] as? [String] ?? []
            return assignments.enumerated().map { index, selected in
                label(index, in: items) + ": " + selected.map { label($0, in: categories) }.joined(separator: ", ")
            }.joined(separator: "\n")
        }
        if let choices = answer["choices"] as? [Int], let groups = details["groups"] as? [[String]] {
            return choices.enumerated().map { index, choice in
                "Gap \(index + 1): " + label(choice, in: groups.indices.contains(index) ? groups[index] : [])
            }.joined(separator: "\n")
        }
        return response
    }
}
