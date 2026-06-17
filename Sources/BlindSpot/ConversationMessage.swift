import Foundation

struct ConversationMessage: Codable {
    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    struct ImageAttachment: Codable {
        let base64PNG: String
    }

    let role: Role
    let content: String
    var image: ImageAttachment?

    init(role: Role, content: String, image: ImageAttachment? = nil) {
        self.role = role
        self.content = content
        self.image = image
    }
}
