import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var overlayController: OverlayWindowController?
    private var menuBarController: MenuBarController?
    private var onboardingController = OnboardingWindowController()
    private var settingsController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar icon — always present
        menuBarController = MenuBarController { [weak self] in
            self?.settingsController.show()
        }

        // Global hotkey
        hotkeyManager = HotkeyManager { [weak self] in
            self?.handleHotkey()
        }
        hotkeyManager?.start()

        // Show onboarding on first launch
        if !PreferencesStore.shared.onboardingComplete {
            onboardingController.onComplete = { [weak self] in
                self?.menuBarController?.rebuildMenu()
            }
            onboardingController.show()
        }
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
