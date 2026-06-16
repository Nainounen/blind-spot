import Foundation
import AppKit

// MARK: - Folder model

struct Folder: Codable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

// MARK: - Conversation model

struct Conversation: Codable, Identifiable {
    var id: UUID
    var title: String
    var messages: [ConversationMessage]
    var profileId: UUID
    var folderId: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        messages: [ConversationMessage] = [],
        profileId: UUID,
        folderId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.profileId = profileId
        self.folderId = folderId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Export helpers

extension Conversation {
    func toMarkdown() -> String {
        var lines: [String] = ["# \(title.isEmpty ? "Untitled" : title)", ""]
        for message in messages where message.role != .system {
            let label = message.role == .user ? "**You**" : "**Assistant**"
            lines += ["\(label):", "", message.content, "", "---", ""]
        }
        return lines.joined(separator: "\n")
    }
}

enum ExportFormat { case markdown, json }

@MainActor
func exportConversation(_ conversation: Conversation, format: ExportFormat) {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    let safeName = conversation.title.isEmpty ? "conversation" : conversation.title
    switch format {
    case .markdown:
        panel.nameFieldStringValue = "\(safeName).md"
    case .json:
        panel.nameFieldStringValue = "\(safeName).json"
    }
    panel.begin { result in
        guard result == .OK, let url = panel.url else { return }
        switch format {
        case .markdown:
            try? conversation.toMarkdown().write(to: url, atomically: true, encoding: .utf8)
        case .json:
            let enc = JSONEncoder()
            enc.outputFormatting = .prettyPrinted
            enc.dateEncodingStrategy = .iso8601
            if let data = try? enc.encode(conversation) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}

// MARK: - Store

@MainActor
@Observable
final class ConversationStore {
    static let shared = ConversationStore()

    private(set) var conversations: [Conversation] = []
    private(set) var folders: [Folder] = []

    private static var dir: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blind-spot/conversations")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var foldersURL: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blind-spot")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("folders.json")
    }

    private let maxCount = 100

    private init() {
        load()
        loadFolders()
        migrateHistory()
    }

    // MARK: - Conversation CRUD

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

    func moveConversation(_ convId: UUID, toFolder folderId: UUID?) {
        guard let conv = conversations.first(where: { $0.id == convId }) else { return }
        var updated = conv
        updated.folderId = folderId
        upsert(updated)
    }

    // MARK: - Folder CRUD

    @discardableResult
    func createFolder(name: String) -> Folder {
        let folder = Folder(name: name)
        folders.append(folder)
        persistFolders()
        NotificationCenter.default.post(name: .conversationsDidUpdate, object: nil)
        return folder
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].name = name
        persistFolders()
        NotificationCenter.default.post(name: .conversationsDidUpdate, object: nil)
    }

    func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        persistFolders()
        for conv in conversations where conv.folderId == id {
            var updated = conv
            updated.folderId = nil
            persist(updated)
            if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
                conversations[idx] = updated
            }
        }
        NotificationCenter.default.post(name: .conversationsDidUpdate, object: nil)
    }

    func conversations(inFolder id: UUID) -> [Conversation] {
        conversations.filter { $0.folderId == id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var unfolderedConversations: [Conversation] {
        conversations.filter { $0.folderId == nil }
    }

    // MARK: - Persistence

    private func load() {
        let dir = Self.dir
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
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

    private func loadFolders() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Self.foldersURL),
           let loaded = try? decoder.decode([Folder].self, from: data) {
            folders = loaded
        }
    }

    private func persistFolders() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(folders) {
            try? data.write(to: Self.foldersURL, options: .atomic)
        }
    }

    private func pruneIfNeeded() {
        guard conversations.count > maxCount else { return }
        let excess = Array(conversations.suffix(from: maxCount))
        for conv in excess { delete(conv.id) }
    }

    // MARK: - Migration from HistoryStore

    private func migrateHistory() {
        guard conversations.isEmpty else { return }
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "blindSpotHistory"),
              let entries = try? JSONDecoder().decode([LegacyHistoryEntry].self, from: data)
        else { return }

        let profileId = ProfilesStore.shared.activeProfile.id
        for entry in entries {
            let conv = Conversation(
                title: String(entry.query.prefix(60)).trimmingCharacters(in: .whitespaces),
                messages: [
                    ConversationMessage(role: .user, content: entry.query),
                    ConversationMessage(role: .assistant, content: entry.response)
                ],
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

private struct LegacyHistoryEntry: Codable {
    let id: UUID
    let query: String
    let response: String
    let providerRaw: String
    let date: Date
}
