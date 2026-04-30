import Foundation
import AppKit
import Combine

@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    private let defaults = UserDefaults.standard

    // MARK: - Published

    @Published var providerChoice: Provider
    @Published var modelOverrides: [String: String]
    @Published var onboardingComplete: Bool

    private init() {
        onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
        providerChoice = Provider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .openai
        if let data = UserDefaults.standard.data(forKey: "modelOverrides"),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            modelOverrides = map
        } else {
            modelOverrides = [:]
        }
    }

    // MARK: - Setters

    func setProvider(_ p: Provider) {
        providerChoice = p
        defaults.set(p.rawValue, forKey: "provider")
    }

    func setModel(_ model: String, for provider: Provider) {
        modelOverrides[provider.rawValue] = model.isEmpty ? nil : model
        if let data = try? JSONEncoder().encode(modelOverrides) {
            defaults.set(data, forKey: "modelOverrides")
        }
    }

    func currentModel(for provider: Provider) -> String {
        modelOverrides[provider.rawValue] ?? provider.defaultModel
    }

    func completeOnboarding() {
        onboardingComplete = true
        defaults.set(true, forKey: "onboardingComplete")
    }

    // MARK: - API keys (stored per-provider in ~/.config/blind-spot/keys/)

    func hasKey(for provider: Provider) -> Bool {
        provider.requiresKey ? !loadKey(for: provider).isEmpty : true
    }

    func loadKey(for provider: Provider) -> String {
        guard provider.requiresKey else { return "" }
        return (try? String(contentsOf: keyURL(for: provider), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func saveKey(_ key: String, for provider: Provider) {
        let url = keyURL(for: provider)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? key.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func clearKey(for provider: Provider) {
        try? FileManager.default.removeItem(at: keyURL(for: provider))
    }

    private func keyURL(for provider: Provider) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blind-spot/keys/\(provider.rawValue)")
    }

    // MARK: - Accessibility

    var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
}
