import Foundation

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let query: String
    let response: String
    let providerRaw: String
    let date: Date
}

@MainActor
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var entries: [HistoryEntry] = []
    private let key = "blindSpotHistory"

    private init() { load() }

    func add(query: String, response: String) {
        let entry = HistoryEntry(
            id: UUID(),
            query: query,
            response: response,
            providerRaw: Config.provider.rawValue,
            date: Date()
        )
        entries.insert(entry, at: 0)
        if entries.count > 10 { entries = Array(entries.prefix(10)) }
        persist()
        NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

extension Notification.Name {
    static let historyDidUpdate = Notification.Name("BlindSpotHistoryDidUpdate")
}
