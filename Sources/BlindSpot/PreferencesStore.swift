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
    @Published var hotkey: Hotkey
    /// True while the user is recording a new hotkey in Settings. The global
    /// `HotkeyManager` watches this and pauses its event tap so the user can
    /// re-record the same combo they're currently bound to.
    @Published var isRecordingHotkey: Bool = false

    /// Names of models installed on the local Ollama server (e.g. `llama3.2:latest`).
    @Published var installedOllamaModels: [String] = []
    /// True when the most recent attempt to reach Ollama failed.
    @Published var ollamaUnreachable: Bool = false

    /// Global system prompt applied to every request when no named
    /// `BLIND_SPOT_PROMPT` is set. Persisted at
    /// ~/.config/blind-spot/system-prompt.txt.
    @Published var systemPrompt: String = ""

    private init() {
        onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
        providerChoice = Provider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .openai
        if let data = UserDefaults.standard.data(forKey: "modelOverrides"),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            modelOverrides = map
        } else {
            modelOverrides = [:]
        }
        if let data = UserDefaults.standard.data(forKey: "hotkey"),
           let hk = try? JSONDecoder().decode(Hotkey.self, from: data) {
            hotkey = hk
        } else {
            hotkey = .default
        }
        systemPrompt = Self.loadSystemPromptFromDisk()
    }

    // MARK: - System prompt

    private static func systemPromptURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/blind-spot/system-prompt.txt")
    }

    private static func loadSystemPromptFromDisk() -> String {
        (try? String(contentsOf: systemPromptURL(), encoding: .utf8)) ?? ""
    }

    /// Persists the prompt to disk. Empty string deletes the file so
    /// `Config.systemPrompt` falls back to the named-prompt code path.
    func saveSystemPrompt(_ prompt: String) {
        systemPrompt = prompt
        let url = Self.systemPromptURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if prompt.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try? prompt.write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
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

    // MARK: - Hotkey

    func setHotkey(_ hk: Hotkey) {
        hotkey = hk
        if let data = try? JSONEncoder().encode(hk) {
            defaults.set(data, forKey: "hotkey")
        }
    }

    func resetHotkey() { setHotkey(.default) }

    // MARK: - Ollama

    /// Hits the local Ollama server, refreshes the installed-model list, and
    /// — if the currently configured Ollama model isn't installed — switches
    /// to the best installed one. Safe to call any time; no-op when Ollama
    /// isn't running.
    func refreshOllamaModels() async {
        guard let models = await OllamaService.listInstalledModels() else {
            ollamaUnreachable = true
            installedOllamaModels = []
            return
        }
        ollamaUnreachable = false
        installedOllamaModels = models.map { $0.name }

        let current = currentModel(for: .ollama)
        let isCurrentInstalled = installedOllamaModels.contains(current)
        if !isCurrentInstalled, let best = OllamaService.bestInstalledModel(in: models) {
            setModel(best.name, for: .ollama)
        }
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
