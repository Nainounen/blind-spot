import AppKit
import SwiftUI
import Combine

@MainActor
final class AutoAnswerProgress {
    static let shared = AutoAnswerProgress()

    private var panel: NSPanel?
    private var timer: Timer?
    private var activityID: UUID?
    private var browserPID: pid_t?
    private var appearanceSubscription: AnyCancellable?

    func begin() -> UUID {
        dismiss()
        let id = UUID()
        activityID = id
        browserPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 128, height: 36),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: AutoAnswerProgressView())
        self.panel = panel
        appearanceSubscription = PreferencesStore.shared.$panelAppearanceMode.sink { [weak panel] mode in
            switch mode {
            case .system: panel?.appearance = nil
            case .light: panel?.appearance = NSAppearance(named: .aqua)
            case .dark: panel?.appearance = NSAppearance(named: .darkAqua)
            }
        }
        updatePosition()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updatePosition() }
        }
        return id
    }

    func end(_ id: UUID) {
        guard activityID == id else { return }
        dismiss()
    }

    func dismiss() {
        appearanceSubscription = nil
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        activityID = nil
        browserPID = nil
    }

    private func updatePosition() {
        guard let panel else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == browserPID else {
            panel.orderOut(nil)
            return
        }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) else { return }
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let size = panel.frame.size
        var origin = NSPoint(x: pointer.x + 18, y: pointer.y - size.height - 12)
        if origin.x + size.width > bounds.maxX { origin.x = pointer.x - size.width - 18 }
        if origin.y < bounds.minY { origin.y = pointer.y + 18 }
        origin.x = max(bounds.minX, min(origin.x, bounds.maxX - size.width))
        origin.y = max(bounds.minY, min(origin.y, bounds.maxY - size.height))
        panel.setFrameOrigin(origin)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}

private struct AutoAnswerProgressView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            if reduceMotion {
                Image(systemName: "hourglass")
            } else {
                ProgressView().controlSize(.small)
            }
            Text("Answering…").font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Auto-Answer is working")
    }
}
