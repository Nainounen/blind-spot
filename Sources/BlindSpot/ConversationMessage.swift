import Foundation

struct ConversationMessage {
    enum Role: String {
        case system
        case user
        case assistant
    }
    let role: Role
    let content: String
}
