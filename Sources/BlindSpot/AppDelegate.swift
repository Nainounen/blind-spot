import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var overlayController: OverlayWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkeyManager = HotkeyManager { [weak self] in
            self?.handleHotkey()
        }
        hotkeyManager?.start()
    }

    private func handleHotkey() {
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
