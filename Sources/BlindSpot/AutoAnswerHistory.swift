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

extension ExamBridge {
    /// Stable key grouping all auto-answer runs on the same exam page into one conversation.
    func historySessionKey(pageURL: String?) -> String {
        let url = pageURL.flatMap { URL(string: $0) }
        let identity = [bundleID, String(processID), url?.host ?? "", url?.path ?? ""].joined(separator: "\n")
        // Do not persist the participant URL or any access token in chat metadata.
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var historyTitle: String {
        "Auto-Answer"
    }
}
