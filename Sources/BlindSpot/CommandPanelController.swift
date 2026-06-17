import AppKit
import SwiftUI

// MARK: - Borderless panel subclass
// NSWindow with styleMask:.borderless returns false for canBecomeKey by default.
// NSPanel returns true — but we make it explicit to be safe.

private class CommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

@MainActor
final class CommandPanelController: NSObject, NSWindowDelegate {
    static let shared = CommandPanelController()

    let vm = CommandPanelViewModel()
    private var panel: CommandPanel?
    private var streamTask: Task<Void, Never>?
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var globalEscMonitor: Any?

    private override init() {}

    // MARK: - Public API

    /// Show the panel. If `query` is non-nil and non-empty, immediately starts a
    /// new conversation with that text (selected-text hotkey flow). If nil or empty,
    /// opens the panel in free-form mode so the user can type.
    func show(query: String?) {
        previousApp = NSWorkspace.shared.frontmostApplication
        buildPanelIfNeeded()
        resizePanel(animated: false)

        let profile = ProfilesStore.shared.activeProfile
        vm.startNewConversation(profileId: profile.id)

        panel?.makeKeyAndOrderFront(nil)
        // Activate the app so the panel appears above the previously-active app.
        // The deprecated flag is ignored on macOS 14+ (behaves as polite activation),
        // but activation is still granted because we're responding to a user event.
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()

        if let q = query, !q.isEmpty {
            startTurn(userText: q)
        } else {
            vm.focusInput = true
        }
    }

    /// Restore and display an existing conversation.
    func show(conversation: Conversation) {
        previousApp = NSWorkspace.shared.frontmostApplication
        buildPanelIfNeeded()
        resizePanel(animated: false)
        vm.loadConversation(conversation)
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
    }

    func hide() {
        streamTask?.cancel()
        removeKeyMonitor()
        panel?.orderOut(nil)
        let prev = previousApp
        previousApp = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            prev?.activate()
        }
    }

    func sendFollowUp(_ text: String) {
        guard !vm.isLoading else { return }
        startTurn(userText: text)
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        vm.isLoading = false
    }

    /// Resize the panel to match the current size preset and conversation state.
    /// For XS, the panel expands when there is content and collapses when empty.
    func resizePanel(animated: Bool) {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let preset = PreferencesStore.shared.panelSizePreset
        let width = preset.width(for: screen)
        let hasContent = !vm.turns.isEmpty || vm.isLoading
        let height = (preset == .xs && !hasContent) ? preset.baseHeight : preset.expandedHeight
        let x = screen.frame.origin.x + (screen.frame.width - width) / 2
        let y = screen.frame.origin.y + screen.frame.height * 0.55 - height / 2
        let newFrame = NSRect(x: x, y: y, width: width, height: height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
    }

    func selectConversation(_ conv: Conversation) {
        streamTask?.cancel()
        vm.loadConversation(conv)
    }

    func newConversation() {
        streamTask?.cancel()
        vm.startNewConversation(profileId: ProfilesStore.shared.activeProfile.id)
        vm.focusInput = true
        resizePanel(animated: true)
    }

    // MARK: - Conversation / streaming

    private func startTurn(userText: String) {
        let profile = ProfilesStore.shared.activeProfile

        // Inject system prompt on first turn
        if vm.turns.isEmpty && !profile.systemPrompt.isEmpty {
            vm.activeConversation?.messages.append(
                ConversationMessage(role: .system, content: profile.systemPrompt)
            )
        }
        vm.activeConversation?.messages.append(
            ConversationMessage(role: .user, content: userText)
        )

        let turnIndex = vm.turns.count
        vm.turns.append(CommandPanelViewModel.Turn(query: userText, response: ""))
        vm.isLoading = true
        vm.errorMessage = nil
        resizePanel(animated: true)

        // Auto-title the conversation from the first query
        if turnIndex == 0 && (vm.activeConversation?.title.isEmpty ?? true) {
            vm.activeConversation?.title = String(userText.prefix(60))
                .trimmingCharacters(in: .whitespaces)
        }

        let msgSnapshot = vm.activeConversation?.messages ?? []

        streamTask = Task {
            do {
                let stream = try await AIService.query(msgSnapshot, profile: profile)
                var fullResponse = ""
                for try await chunk in stream {
                    fullResponse += chunk
                    await MainActor.run {
                        guard turnIndex < vm.turns.count else { return }
                        vm.turns[turnIndex].response += chunk
                    }
                }
                let completed = fullResponse
                await MainActor.run {
                    vm.isLoading = false
                    guard !completed.isEmpty else {
                        if !Task.isCancelled {
                            vm.errorMessage = "No response — try increasing Max Output Tokens in the profile settings."
                        }
                        return
                    }
                    vm.activeConversation?.messages.append(
                        ConversationMessage(role: .assistant, content: completed)
                    )
                    if let conv = vm.activeConversation {
                        ConversationStore.shared.upsert(conv)
                        vm.activeConversation = ConversationStore.shared.conversation(id: conv.id)
                    }
                    if PreferencesStore.shared.autoCopyLastResponse {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(completed, forType: .string)
                    }
                }
            } catch {
                await MainActor.run {
                    vm.isLoading = false
                    if !(error is CancellationError) {
                        vm.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard PreferencesStore.shared.closeOnFocusLoss else { return }
        // Defer one run loop so NSApp.keyWindow reflects the new state.
        // If an alert or sheet within BlindSpot is now key, don't hide.
        DispatchQueue.main.async { [weak self] in
            guard NSApp.keyWindow == nil else { return }
            self?.hide()
        }
    }

    func windowWillClose(_ notification: Notification) {
        streamTask?.cancel()
        removeKeyMonitor()
        panel = nil
    }

    // MARK: - Key monitors

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }

        // Local monitor handles Cmd shortcuts when the panel is key
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // ESC
                // Let the sheet handle ESC when an alert/confirmationDialog is shown
                if self.panel?.attachedSheet != nil { return event }
                Task { @MainActor in self.hide() }
                return nil
            }
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "n":
                    Task { @MainActor in self.newConversation() }
                    return nil
                case "k", "f":
                    Task { @MainActor in self.vm.focusSidebarSearch = true }
                    return nil
                case "w":
                    Task { @MainActor in self.hide() }
                    return nil
                default: break
                }
            }
            // Ctrl+C cancels active stream
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control,
               event.charactersIgnoringModifiers == "c",
               self.vm.isLoading {
                Task { @MainActor in self.cancelStream() }
                return nil
            }
            return event
        }

        // Global monitor fires ESC even when another app is frontmost
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return }
            if self.panel?.attachedSheet != nil { return }
            Task { @MainActor in self.hide() }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = globalEscMonitor { NSEvent.removeMonitor(m); globalEscMonitor = nil }
    }

    // MARK: - Panel setup

    private func buildPanelIfNeeded() {
        guard panel == nil else { return }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let preset = PreferencesStore.shared.panelSizePreset
        let width = preset.width(for: screen)
        let height = preset.baseHeight

        let p = CommandPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.hidesOnDeactivate = false
        let isDemo = ProcessInfo.processInfo.environment["BLIND_SPOT_DEMO"] == "1"
        p.sharingType = isDemo ? .readOnly : .none
        p.isMovableByWindowBackground = true
        p.delegate = self

        let hostingView = NSHostingView(rootView:
            CommandPanelView(
                vm: vm,
                onClose: { [weak self] in self?.hide() },
                onFollowUp: { [weak self] text in self?.sendFollowUp(text) },
                onSelectConversation: { [weak self] conv in self?.selectConversation(conv) },
                onNewConversation: { [weak self] in self?.newConversation() },
                onCancel: { [weak self] in self?.cancelStream() }
            )
        )

        let glassView = NSGlassEffectView()
        glassView.cornerRadius = 16
        glassView.clipsToBounds = true
        glassView.contentView = hostingView
        p.contentView = glassView

        // Position: centered horizontally, 55% from bottom of screen
        let x = screen.frame.origin.x + (screen.frame.width - width) / 2
        let y = screen.frame.origin.y + screen.frame.height * 0.55 - height / 2
        p.setFrameOrigin(NSPoint(x: x, y: y))

        self.panel = p
    }
}
