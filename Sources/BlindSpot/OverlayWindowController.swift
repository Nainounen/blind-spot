import AppKit
import SwiftUI

class OverlayWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let vm = OverlayViewModel()
    private var streamTask: Task<Void, Never>?
    private var conversationMessages: [ConversationMessage] = []
    private var keyEventMonitor: Any?

    // MARK: - Public

    func show(query: String) {
        if panel == nil { buildPanel() }
        streamTask?.cancel()
        conversationMessages = []
        vm.turns = []
        vm.followUpText = ""
        vm.errorMessage = nil
        vm.isCopied = false
        vm.isLoading = !query.isEmpty

        panel?.orderFrontRegardless()
        installKeyMonitor()

        guard !query.isEmpty else { return }

        if let s = Config.systemPrompt {
            conversationMessages.append(ConversationMessage(role: .system, content: s))
        }
        startTurn(userText: query)
    }

    /// Restores a history entry and allows follow-up questions.
    func show(entry: HistoryEntry) {
        if panel == nil { buildPanel() }
        streamTask?.cancel()
        vm.errorMessage = nil
        vm.isCopied = false
        vm.isLoading = false
        vm.followUpText = ""
        vm.turns = [OverlayViewModel.Turn(query: entry.query, response: entry.response)]

        conversationMessages = []
        if let s = Config.systemPrompt {
            conversationMessages.append(ConversationMessage(role: .system, content: s))
        }
        conversationMessages.append(ConversationMessage(role: .user, content: entry.query))
        conversationMessages.append(ConversationMessage(role: .assistant, content: entry.response))

        panel?.orderFrontRegardless()
        installKeyMonitor()
    }

    func hide() {
        streamTask?.cancel()
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    // MARK: - Conversation

    func sendFollowUp(_ text: String) {
        guard !vm.isLoading else { return }
        startTurn(userText: text)
    }

    private func startTurn(userText: String) {
        conversationMessages.append(ConversationMessage(role: .user, content: userText))

        let turnIndex = vm.turns.count
        vm.turns.append(OverlayViewModel.Turn(query: userText, response: ""))
        vm.isLoading = true
        vm.errorMessage = nil

        let isFirstTurn = turnIndex == 0
        let firstQuery = vm.turns.first?.query ?? userText
        let msgSnapshot = conversationMessages

        streamTask = Task {
            do {
                let stream = try await AIService.query(msgSnapshot)
                var fullResponse = ""
                for try await chunk in stream {
                    fullResponse += chunk
                    await MainActor.run {
                        guard turnIndex < vm.turns.count else { return }
                        var updated = vm.turns[turnIndex]
                        updated.response += chunk
                        vm.turns[turnIndex] = updated
                    }
                }
                let completedResponse = fullResponse
                await MainActor.run {
                    vm.isLoading = false
                    conversationMessages.append(
                        ConversationMessage(role: .assistant, content: completedResponse)
                    )
                    if isFirstTurn {
                        HistoryStore.shared.add(query: firstQuery, response: completedResponse)
                    }
                }
            } catch {
                await MainActor.run {
                    vm.isLoading = false
                    vm.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - ESC key (global monitor fires even when another app is frontmost)

    private func installKeyMonitor() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.panel?.isVisible == true else { return }
            Task { @MainActor in self.hide() }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyEventMonitor {
            NSEvent.removeMonitor(m)
            keyEventMonitor = nil
        }
    }

    deinit { removeKeyMonitor() }

    // MARK: - Panel

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 440),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "BlindSpot"
        // BLIND_SPOT_DEMO=1 makes the overlay visible to screen recorders (for demos/screenshots only)
        let isDemo = ProcessInfo.processInfo.environment["BLIND_SPOT_DEMO"] == "1"
        p.sharingType = isDemo ? .readOnly : .none
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.titlebarAppearsTransparent = true
        p.delegate = self
        p.center()

        p.contentView = NSHostingView(
            rootView: OverlayView(
                vm: vm,
                onClose: { [weak self] in self?.hide() },
                onFollowUp: { [weak self] text in self?.sendFollowUp(text) }
            )
            .background(.ultraThickMaterial)
            .cornerRadius(12)
        )
        self.panel = p
    }

    func windowWillClose(_ notification: Notification) {
        streamTask?.cancel()
        removeKeyMonitor()
    }
}
