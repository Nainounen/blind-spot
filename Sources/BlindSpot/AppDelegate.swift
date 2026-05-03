import AppKit
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var overlayController: OverlayWindowController?
    private var menuBarController: MenuBarController?
    private var onboardingController = OnboardingWindowController()
    private var settingsController = SettingsWindowController()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Provide Edit-menu keyboard shortcuts (Cmd+V/C/X/A/Z) for all text
        // fields and text views. The menu bar stays hidden in .accessory policy
        // but the key equivalents are registered and work globally.
        NSApp.mainMenu = buildEditMenu()

        // Menu bar icon — always present
        menuBarController = MenuBarController(
            onSettings: { [weak self] in self?.settingsController.show() },
            onShowHistory: { [weak self] entry in self?.showOverlay(entry: entry) }
        )

        // Global hotkey — read initial value from prefs and start listening
        let manager = HotkeyManager(hotkey: PreferencesStore.shared.hotkey) { [weak self] in
            self?.handleHotkey()
        }
        manager.start()
        hotkeyManager = manager

        // Live-update the tap when the user changes the hotkey in Settings.
        PreferencesStore.shared.$hotkey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hk in self?.hotkeyManager?.update(to: hk) }
            .store(in: &cancellables)

        // Pause the tap while the user is recording so we don't swallow the
        // very keystroke they're trying to bind.
        PreferencesStore.shared.$isRecordingHotkey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                if recording { self?.hotkeyManager?.pause() }
                else         { self?.hotkeyManager?.resume() }
            }
            .store(in: &cancellables)

        // Show onboarding on first launch
        if !PreferencesStore.shared.onboardingComplete {
            onboardingController.onComplete = { [weak self] in
                self?.menuBarController?.rebuildMenu()
            }
            onboardingController.show()
        }

        // If the user is already on Ollama, make sure the configured model is
        // actually installed. Picks the best installed one otherwise.
        if PreferencesStore.shared.providerChoice == .ollama {
            Task { await PreferencesStore.shared.refreshOllamaModels() }
        }
    }

    /// Without this override, AppKit terminates the process the moment the
    /// last visible window closes while the app is in `.regular` activation
    /// policy — which is exactly what happens when the user closes the
    /// Settings window. We're a menu-bar app; the status item should keep
    /// the process alive.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func handleHotkey() {
        // Silently skip if onboarding is not done — hotkey shouldn't fire yet
        guard PreferencesStore.shared.onboardingComplete else { return }

        TextCapture.getSelectedText { [weak self] text in
            DispatchQueue.main.async {
                self?.showOverlay(query: text ?? "")
            }
        }
    }

    private func showOverlay(query: String) {
        if overlayController == nil { overlayController = OverlayWindowController() }
        overlayController?.show(query: query)
    }

    private func showOverlay(entry: HistoryEntry) {
        if overlayController == nil { overlayController = OverlayWindowController() }
        overlayController?.show(entry: entry)
    }

    private func buildEditMenu() -> NSMenu {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo",  action: Selector(("undo:")),  keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")),  keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut",        action: #selector(NSText.cut(_:)),       keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",       action: #selector(NSText.copy(_:)),      keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",      action: #selector(NSText.paste(_:)),     keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        let menu = NSMenu()
        menu.addItem(editItem)
        return menu
    }
}
