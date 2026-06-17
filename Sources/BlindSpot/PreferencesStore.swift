import Foundation
import AppKit
import Combine

// MARK: - Panel size preset

enum PanelSizePreset: String, CaseIterable, Identifiable {
    case xs, small, medium, large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xs:     return "XS"
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }

    // XS expands vertically when there is conversation content
    var baseHeight: CGFloat {
        switch self {
        case .xs:     return 90
        case .small:  return 440
        case .medium: return 560
        case .large:  return 700
        }
    }

    var expandedHeight: CGFloat {
        switch self {
        case .xs: return 340
        default:  return baseHeight
        }
    }

    private var maxWidth: CGFloat {
        switch self {
        case .xs:     return 580
        case .small:  return 680
        case .medium: return 880
        case .large:  return 1080
        }
    }

    private var widthRatio: CGFloat {
        switch self {
        case .xs:     return 0.50
        case .small:  return 0.65
        case .medium: return 0.80
        case .large:  return 0.88
        }
    }

    func width(for screen: NSScreen) -> CGFloat {
        min(screen.frame.width * widthRatio, maxWidth)
    }
}

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
    @Published var panicHotkey: Hotkey
    @Published var isRecordingPanicHotkey: Bool = false
    @Published var autoAnswerHotkey: Hotkey
    @Published var isRecordingAutoAnswerHotkey: Bool = false
    @Published var answerAllHotkey: Hotkey
    @Published var isRecordingAnswerAllHotkey: Bool = false
    @Published var visualContextHotkey: Hotkey
    @Published var isRecordingVisualContextHotkey: Bool = false

    /// Names of models installed on the local Ollama server (e.g. `llama3.2:latest`).
    @Published var installedOllamaModels: [String] = []
    /// True when the most recent attempt to reach Ollama failed.
    @Published var ollamaUnreachable: Bool = false

    /// Maximum tokens per response. Stored in UserDefaults "maxTokens". Default 4096.
    @Published var maxTokens: Int

    /// When true, the command panel closes automatically when it loses keyboard focus
    /// (i.e. the user clicks in another app). Default false — panel stays open.
    @Published var closeOnFocusLoss: Bool

    /// When true, the last AI response is automatically copied to the clipboard
    /// as soon as streaming completes.
    @Published var autoCopyLastResponse: Bool

    /// Size preset for the command panel. Default is medium (880 × 560).
    @Published var panelSizePreset: PanelSizePreset

    /// When true, the panel remembers its last dragged position and restores it
    /// on next open instead of centering on screen.
    @Published var savePanelPosition: Bool

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
        if let data = UserDefaults.standard.data(forKey: "panicHotkey"),
           let hk = try? JSONDecoder().decode(Hotkey.self, from: data) {
            panicHotkey = hk
        } else {
            panicHotkey = .defaultPanic
        }
        if let data = UserDefaults.standard.data(forKey: "autoAnswerHotkey"),
           let hk = try? JSONDecoder().decode(Hotkey.self, from: data) {
            autoAnswerHotkey = hk
        } else {
            autoAnswerHotkey = .defaultAutoAnswer
        }
        if let data = UserDefaults.standard.data(forKey: "answerAllHotkey"),
           let hk = try? JSONDecoder().decode(Hotkey.self, from: data) {
            answerAllHotkey = hk
        } else {
            answerAllHotkey = .defaultAnswerAll
        }
        if let data = UserDefaults.standard.data(forKey: "visualContextHotkey"),
           let hk = try? JSONDecoder().decode(Hotkey.self, from: data) {
            visualContextHotkey = hk
        } else {
            visualContextHotkey = .defaultVisualContext
        }
        let storedMax = UserDefaults.standard.integer(forKey: "maxTokens")
        maxTokens = storedMax > 0 ? storedMax : 4096
        closeOnFocusLoss = UserDefaults.standard.bool(forKey: "closeOnFocusLoss")
        autoCopyLastResponse = UserDefaults.standard.bool(forKey: "autoCopyLastResponse")
        panelSizePreset = PanelSizePreset(rawValue: UserDefaults.standard.string(forKey: "panelSizePreset") ?? "") ?? .medium
        savePanelPosition = UserDefaults.standard.bool(forKey: "savePanelPosition")
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

    func setPanicHotkey(_ hk: Hotkey) {
        panicHotkey = hk
        if let data = try? JSONEncoder().encode(hk) {
            defaults.set(data, forKey: "panicHotkey")
        }
    }

    func resetPanicHotkey() { setPanicHotkey(.defaultPanic) }

    func setAutoAnswerHotkey(_ hk: Hotkey) {
        autoAnswerHotkey = hk
        if let data = try? JSONEncoder().encode(hk) {
            defaults.set(data, forKey: "autoAnswerHotkey")
        }
    }

    func resetAutoAnswerHotkey() { setAutoAnswerHotkey(.defaultAutoAnswer) }

    func setAnswerAllHotkey(_ hk: Hotkey) {
        answerAllHotkey = hk
        if let data = try? JSONEncoder().encode(hk) {
            defaults.set(data, forKey: "answerAllHotkey")
        }
    }

    func resetAnswerAllHotkey() { setAnswerAllHotkey(.defaultAnswerAll) }

    func setVisualContextHotkey(_ hk: Hotkey) {
        visualContextHotkey = hk
        if let data = try? JSONEncoder().encode(hk) {
            defaults.set(data, forKey: "visualContextHotkey")
        }
    }

    func resetVisualContextHotkey() { setVisualContextHotkey(.defaultVisualContext) }

    func setMaxTokens(_ tokens: Int) {
        maxTokens = max(256, min(8192, tokens))
        defaults.set(maxTokens, forKey: "maxTokens")
    }

    func setCloseOnFocusLoss(_ value: Bool) {
        closeOnFocusLoss = value
        defaults.set(value, forKey: "closeOnFocusLoss")
    }

    func setAutoCopyLastResponse(_ value: Bool) {
        autoCopyLastResponse = value
        defaults.set(value, forKey: "autoCopyLastResponse")
    }

    func setPanelSizePreset(_ preset: PanelSizePreset) {
        panelSizePreset = preset
        defaults.set(preset.rawValue, forKey: "panelSizePreset")
    }

    func setSavePanelPosition(_ value: Bool) {
        savePanelPosition = value
        defaults.set(value, forKey: "savePanelPosition")
        if !value {
            clearSavedPanelCenter()
        }
    }

    // MARK: - Panel position persistence

    /// Saved panel center point in screen coordinates, or nil if never dragged.
    var savedPanelCenter: NSPoint? {
        let x = UserDefaults.standard.double(forKey: "panelCenterX")
        let y = UserDefaults.standard.double(forKey: "panelCenterY")
        guard x != 0 || y != 0 else { return nil }
        return NSPoint(x: x, y: y)
    }

    func savePanelCenter(_ point: NSPoint) {
        guard savePanelPosition else { return }
        UserDefaults.standard.set(point.x, forKey: "panelCenterX")
        UserDefaults.standard.set(point.y, forKey: "panelCenterY")
    }

    private func clearSavedPanelCenter() {
        UserDefaults.standard.removeObject(forKey: "panelCenterX")
        UserDefaults.standard.removeObject(forKey: "panelCenterY")
    }

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
