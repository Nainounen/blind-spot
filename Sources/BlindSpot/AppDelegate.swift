import AppKit
import Combine
import Sparkle

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var panicHotkeyManager: HotkeyManager?
    private var autoAnswerHotkeyManager: HotkeyManager?
    private var answerAllHotkeyManager: HotkeyManager?
    private var visualContextHotkeyManager: HotkeyManager?
    private var menuBarController: MenuBarController?
    private var onboardingController = OnboardingWindowController()
    private var settingsController = SettingsWindowController()
    private var cancellables = Set<AnyCancellable>()
    // Zero-size hidden window kept alive for the entire app lifetime. Prevents
    // AppKit from reaching "no windows" state, which can trigger termination in
    // some macOS activation-policy edge cases even with the delegate override.
    private var ghostWindow: NSWindow?
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Provide Edit-menu keyboard shortcuts (Cmd+V/C/X/A/Z) for all text
        // fields and text views. The menu bar stays hidden in .accessory policy
        // but the key equivalents are registered and work globally.
        NSApp.mainMenu = buildEditMenu()

        // Keep the process alive regardless of which visible windows come and go.
        let ghost = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        ghost.isReleasedWhenClosed = false
        ghostWindow = ghost

        // Auto-update via Sparkle. SUFeedURL and SUPublicEDKey must be set in Info.plist.
        // Pass self as userDriverDelegate so we can activate the app when Sparkle's
        // update window appears — LSUIElement apps never become frontmost on their own,
        // so without this the Updater.app window appears behind other apps and button
        // clicks (including "Install and Relaunch") are swallowed by the foreground app.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )

        // Boot data-layer singletons (triggers migration if first launch)
        _ = ProfilesStore.shared
        _ = ConversationStore.shared

        // Menu bar icon — always present
        menuBarController = MenuBarController(
            onSettings: { [weak self] in self?.settingsController.show() },
            onShowConversation: { conversation in
                CommandPanelController.shared.show(conversation: conversation)
            },
            onCheckForUpdates: { [weak self] in self?.checkForUpdates() }
        )

        // Global hotkey — read initial value from prefs and start listening
        let manager = HotkeyManager(hotkey: PreferencesStore.shared.hotkey) { [weak self] in
            self?.handleHotkey()
        }
        manager.start()
        hotkeyManager = manager

        // Panic hotkey — force-quits the app immediately
        let panicManager = HotkeyManager(hotkey: PreferencesStore.shared.panicHotkey) {
            exit(0)
        }
        panicManager.start()
        panicHotkeyManager = panicManager

        // Auto-answer hotkey — reads question from AX tree, pastes AI answer
        let autoAnswerManager = HotkeyManager(hotkey: PreferencesStore.shared.autoAnswerHotkey) { [weak self] in
            self?.handleAutoAnswerHotkey()
        }
        autoAnswerManager.start()
        autoAnswerHotkeyManager = autoAnswerManager

        // Answer-all hotkey — answers every question in the frontmost window
        let answerAllManager = HotkeyManager(hotkey: PreferencesStore.shared.answerAllHotkey) { [weak self] in
            self?.handleAnswerAllHotkey()
        }
        answerAllManager.start()
        answerAllHotkeyManager = answerAllManager

        // Visual context hotkey (⌘⇧⌥Space) — captures selected text + screenshot
        let visualContextManager = HotkeyManager(
            hotkey: Hotkey(
                keyCode: 49,
                modifiers: NSEvent.ModifierFlags([.command, .shift, .option]).rawValue
            )
        ) { [weak self] in
            self?.handleVisualContextHotkey()
        }
        visualContextManager.start()
        visualContextHotkeyManager = visualContextManager

        // Live-update the tap when the user changes the hotkey in Settings.
        PreferencesStore.shared.$hotkey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hk in self?.hotkeyManager?.update(to: hk) }
            .store(in: &cancellables)

        PreferencesStore.shared.$panicHotkey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hk in self?.panicHotkeyManager?.update(to: hk) }
            .store(in: &cancellables)

        PreferencesStore.shared.$autoAnswerHotkey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hk in self?.autoAnswerHotkeyManager?.update(to: hk) }
            .store(in: &cancellables)

        PreferencesStore.shared.$answerAllHotkey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hk in self?.answerAllHotkeyManager?.update(to: hk) }
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

        PreferencesStore.shared.$isRecordingPanicHotkey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                if recording { self?.panicHotkeyManager?.pause() }
                else         { self?.panicHotkeyManager?.resume() }
            }
            .store(in: &cancellables)

        PreferencesStore.shared.$isRecordingAutoAnswerHotkey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                if recording { self?.autoAnswerHotkeyManager?.pause() }
                else         { self?.autoAnswerHotkeyManager?.resume() }
            }
            .store(in: &cancellables)

        PreferencesStore.shared.$isRecordingAnswerAllHotkey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                if recording { self?.answerAllHotkeyManager?.pause() }
                else         { self?.answerAllHotkeyManager?.resume() }
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
                self?.showPanel(query: text ?? "")
            }
        }
    }

    private func handleVisualContextHotkey() {
        guard PreferencesStore.shared.onboardingComplete else { return }

        // Capture AX bounds synchronously before any async work — the focused
        // element may shift once Cmd+E / Cmd+C events fire.
        let fallbackBounds = ScreenshotCapture.selectionOrMouseBounds()

        TextCapture.getSelectedTextWithBounds { result in
            let query = result?.text ?? ""
            let rect = result?.selectionBounds ?? fallbackBounds
            Task { @MainActor in
                let imageData = await ScreenshotCapture.captureRegion(rect)
                CommandPanelController.shared.show(query: query.isEmpty ? nil : query, image: imageData)
            }
        }
    }

    private func handleAutoAnswerHotkey() {
        guard PreferencesStore.shared.onboardingComplete else { return }
        AutoAnswerService.shared.run()
    }

    private func handleAnswerAllHotkey() {
        guard PreferencesStore.shared.onboardingComplete else { return }
        AutoAnswerService.shared.runAnswerAll()
    }

    private func showPanel(query: String) {
        CommandPanelController.shared.show(query: query.isEmpty ? nil : query)
    }

    func checkForUpdates() {
        updaterController?.updater.checkForUpdates()
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

// MARK: - SPUStandardUserDriverDelegate

extension AppDelegate: SPUStandardUserDriverDelegate {
    // Activate so the Updater.app window comes to front and receives clicks.
    // Without this, LSUIElement apps never become frontmost, the "Install and
    // Relaunch" button is unreachable, and the update silently does nothing.
    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
