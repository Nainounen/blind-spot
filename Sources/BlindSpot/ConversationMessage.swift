import Foundation

struct ConversationMessage: Codable {
    enum Role: String, Codable {
        case system
        case user
        case assistant
    }
    let role: Role
    let content: String
}
