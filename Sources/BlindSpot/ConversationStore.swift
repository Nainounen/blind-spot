import Foundation

// MARK: - Model

struct Conversation: Codable, Identifiable {
    var id: UUID
    var title: String
    var messages: [ConversationMessage]
    var profileId: UUID
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        messages: [ConversationMessage] = [],
        profileId: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.profileId = profileId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Store

@MainActor
@Observable
final class ConversationStore {
    static let shared = ConversationStore()

    private(set) var conversations: [Conversation] = []

    private static var dir: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blind-spot/conversations")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private let maxCount = 100

    private init() {
        load()
        migrateHistory()
    }

    // MARK: - CRUD

    func upsert(_ conversation: Conversation) {
        var conv = conversation
        conv.updatedAt = Date()
        if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
            conversations[idx] = conv
        } else {
            conversations.insert(conv, at: 0)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persist(conv)
        pruneIfNeeded()
        NotificationCenter.default.post(name: .conversationsDidUpdate, object: nil)
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        let file = Self.dir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
        NotificationCenter.default.post(name: .conversationsDidUpdate, object: nil)
    }

    func conversation(id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        let dir = Self.dir
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        conversations = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Conversation.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func persist(_ conversation: Conversation) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let file = Self.dir.appendingPathComponent("\(conversation.id.uuidString).json")
        guard let data = try? encoder.encode(conversation) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private func pruneIfNeeded() {
        guard conversations.count > maxCount else { return }
        let excess = Array(conversations.suffix(from: maxCount))
        for conv in excess { delete(conv.id) }
    }

    // MARK: - Migration from HistoryStore (UserDefaults "blindSpotHistory")

    private func migrateHistory() {
        guard conversations.isEmpty else { return }
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "blindSpotHistory"),
              let entries = try? JSONDecoder().decode([LegacyHistoryEntry].self, from: data)
        else { return }

        let profileId = ProfilesStore.shared.activeProfile.id
        for entry in entries {
            let userMsg = ConversationMessage(role: .user, content: entry.query)
            let assistantMsg = ConversationMessage(role: .assistant, content: entry.response)
            let conv = Conversation(
                title: String(entry.query.prefix(60)).trimmingCharacters(in: .whitespaces),
                messages: [userMsg, assistantMsg],
                profileId: profileId,
                createdAt: entry.date,
                updatedAt: entry.date
            )
            persist(conv)
            conversations.append(conv)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        defaults.removeObject(forKey: "blindSpotHistory")
    }
}

extension Notification.Name {
    static let conversationsDidUpdate = Notification.Name("BlindSpotConversationsDidUpdate")
}

// Only used for migration
private struct LegacyHistoryEntry: Codable {
    let id: UUID
    let query: String
    let response: String
    let providerRaw: String
    let date: Date
}
