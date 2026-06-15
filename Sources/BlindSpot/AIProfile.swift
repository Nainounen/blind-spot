import Foundation

// MARK: - Model

struct AIProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var provider: Provider
    var model: String
    var systemPrompt: String
    var maxOutputTokens: Int
    var temperature: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        provider: Provider,
        model: String = "",
        systemPrompt: String = "",
        maxOutputTokens: Int = 4096,
        temperature: Double = 1.0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.model = model.isEmpty ? provider.defaultModel : model
        self.systemPrompt = systemPrompt
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.createdAt = createdAt
    }

    // Synthesized Equatable compares all fields — needed so SwiftUI correctly
    // detects changes in @State<AIProfile> (e.g. provider or model edits).
}

// MARK: - Store

@MainActor
@Observable
final class ProfilesStore {
    static let shared = ProfilesStore()

    private(set) var profiles: [AIProfile] = []
    private(set) var activeProfileId: UUID?

    var activeProfile: AIProfile {
        profiles.first { $0.id == activeProfileId }
            ?? profiles.first
            ?? AIProfile(name: "Default", provider: .openai)
    }

    private static var profilesURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blind-spot")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }

    private init() {
        load()
        if profiles.isEmpty { migrate() }
        if activeProfileId == nil || !profiles.contains(where: { $0.id == activeProfileId }) {
            activeProfileId = profiles.first?.id
            saveActiveId()
        }
    }

    // MARK: - CRUD

    func create(_ profile: AIProfile) {
        profiles.append(profile)
        save()
    }

    func update(_ profile: AIProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }

    func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = profiles.first?.id
            saveActiveId()
        }
        save()
    }

    func duplicate(_ profile: AIProfile) {
        var copy = profile
        copy.id = UUID()
        copy.name = "\(profile.name) Copy"
        copy.createdAt = Date()
        profiles.append(copy)
        save()
    }

    func activate(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        saveActiveId()
    }

    // MARK: - Persistence

    private func load() {
        let url = Self.profilesURL
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        profiles = (try? decoder.decode([AIProfile].self, from: data)) ?? []
        activeProfileId = UserDefaults.standard.string(forKey: "activeProfileId")
            .flatMap { UUID(uuidString: $0) }
    }

    func save() {
        let url = Self.profilesURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(profiles) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func saveActiveId() {
        UserDefaults.standard.set(activeProfileId?.uuidString, forKey: "activeProfileId")
    }

    // MARK: - Migration from legacy flat settings

    private func migrate() {
        let defaults = UserDefaults.standard
        let legacyProvider = Provider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .openai
        let legacyModel: String = {
            if let data = defaults.data(forKey: "modelOverrides"),
               let map = try? JSONDecoder().decode([String: String].self, from: data) {
                return map[legacyProvider.rawValue] ?? legacyProvider.defaultModel
            }
            return legacyProvider.defaultModel
        }()
        let legacyPrompt: String = {
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/blind-spot/system-prompt.txt")
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }()
        let legacyMax = defaults.integer(forKey: "maxTokens")
        let profile = AIProfile(
            name: "Default",
            provider: legacyProvider,
            model: legacyModel,
            systemPrompt: legacyPrompt,
            maxOutputTokens: legacyMax > 0 ? legacyMax : 4096,
            temperature: 1.0
        )
        profiles = [profile]
        activeProfileId = profile.id
        save()
        saveActiveId()
    }
}
