import Foundation

@MainActor
@Observable
final class CommandPanelViewModel {
    struct Turn {
        let query: String
        var response: String
        var hasImage: Bool = false
    }

    var turns: [Turn] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var followUpText: String = ""
    var activeConversation: Conversation? = nil

    // Trigger signals for focus management (set to true, view resets to false)
    var focusInput: Bool = false
    var focusSidebarSearch: Bool = false

    // Sidebar search state
    var sidebarSearch: String = ""

    func startNewConversation(profileId: UUID) {
        activeConversation = Conversation(title: "", messages: [], profileId: profileId)
        turns = []
        isLoading = false
        errorMessage = nil
        followUpText = ""
    }

    func loadConversation(_ conversation: Conversation) {
        activeConversation = conversation
        // Rebuild turns from message pairs (skip system messages)
        var rebuilt: [Turn] = []
        let userAndAssistant = conversation.messages.filter { $0.role != .system }
        var idx = 0
        while idx < userAndAssistant.count {
            let msg = userAndAssistant[idx]
            if msg.role == .user {
                let response = (idx + 1 < userAndAssistant.count && userAndAssistant[idx + 1].role == .assistant)
                    ? userAndAssistant[idx + 1].content : ""
                rebuilt.append(Turn(query: msg.content, response: response, hasImage: msg.image != nil))
                idx += 2
            } else {
                idx += 1
            }
        }
        turns = rebuilt
        isLoading = false
        errorMessage = nil
        followUpText = ""
    }
}
