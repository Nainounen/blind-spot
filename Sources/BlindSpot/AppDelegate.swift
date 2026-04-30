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
        // Menu bar icon — always present
        menuBarController = MenuBarController { [weak self] in
            self?.settingsController.show()
        }

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
        if overlayController == nil {
            overlayController = OverlayWindowController()
        }
        overlayController?.show(query: query)
    }
}
