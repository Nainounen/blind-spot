import AppKit
import SwiftUI

class OverlayWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let vm = OverlayViewModel()
    private var streamTask: Task<Void, Never>?

    func show(query: String) {
        if panel == nil { buildPanel() }

        streamTask?.cancel()
        vm.query = query
        vm.response = ""
        vm.errorMessage = nil
        vm.isLoading = !query.isEmpty

        // orderFront on a nonactivatingPanel brings the window to the top without
        // stealing key focus from the browser. The frontmost app stays unchanged,
        // so no JS blur/visibilitychange event fires in the page.
        panel?.orderFrontRegardless()

        guard !query.isEmpty else { return }

        streamTask = Task {
            do {
                let stream = try await AIService.query(query)
                for try await chunk in stream {
                    await MainActor.run {
                        vm.response += chunk
                    }
                }
                await MainActor.run { vm.isLoading = false }
            } catch {
                await MainActor.run {
                    vm.isLoading = false
                    vm.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func hide() {
        streamTask?.cancel()
        panel?.orderOut(nil)
    }

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "Blind Spot"
        p.sharingType = .none          // invisible to all screen capture tools
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.titlebarAppearsTransparent = true
        p.delegate = self
        p.center()

        p.contentView = NSHostingView(
            rootView: OverlayView(vm: vm, onClose: { [weak self] in self?.hide() })
                .background(.ultraThickMaterial)
                .cornerRadius(12)
        )
        self.panel = p
    }

    func windowWillClose(_ notification: Notification) {
        streamTask?.cancel()
    }
}
