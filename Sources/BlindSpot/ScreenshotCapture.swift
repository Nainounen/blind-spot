import AppKit
import ScreenCaptureKit

enum ScreenshotCapture {
    /// Returns the on-screen bounds of the current text selection (CG coordinates,
    /// origin top-left of primary display), falling back to the mouse cursor.
    static func selectionOrMouseBounds() -> CGRect {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return mouseRect() }
        return TextCapture.exposedBoundsForCurrentSelection(pid: frontApp.processIdentifier) ?? mouseRect()
    }

    /// Captures a padded region around `rect` (CG screen coordinates) as PNG data.
    /// Returns nil if screen recording permission is not granted or capture fails.
    /// Padding and minimum size are read from PreferencesStore so the user can
    /// tune how much context the AI sees.
    static func captureRegion(_ rect: CGRect) async -> Data? {
        let prefs = await MainActor.run { PreferencesStore.shared }
        let pad = await MainActor.run { prefs.screenshotPadding }
        let padded = rect.insetBy(dx: -pad, dy: -pad)

        let minWidth  = await MainActor.run { prefs.screenshotMinWidth }
        let minHeight = await MainActor.run { prefs.screenshotMinHeight }
        let finalRect = CGRect(
            x:      padded.minX,
            y:      padded.minY,
            width:  max(padded.width,  minWidth),
            height: max(padded.height, minHeight)
        )

        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: finalRect.midX, y: finalRect.midY)) })
                              ?? content.displays.first else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])

            // sourceRect must be in the display's local coordinate space (origin 0,0 at display top-left)
            let localRect = CGRect(
                x: finalRect.origin.x - display.frame.origin.x,
                y: finalRect.origin.y - display.frame.origin.y,
                width:  max(1, finalRect.width),
                height: max(1, finalRect.height)
            )

            let config = SCStreamConfiguration()
            config.sourceRect = localRect
            config.width  = max(1, Int(localRect.width))
            config.height = max(1, Int(localRect.height))
            config.scalesToFit = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        } catch {
            return nil
        }
    }

    // MARK: - Frontmost window capture

    /// Captures the frontmost application's top window as PNG data.
    /// Falls back to the region around the mouse if bounds can't be resolved.
    static func captureFrontmostWindow() async -> Data? {
        let bounds = frontmostWindowBounds() ?? mouseRect()
        return await captureRegion(bounds)
    }

    private static func frontmostWindowBounds() -> CGRect? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let windows = list.filter {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
            && (($0[kCGWindowLayer as String] as? Int) ?? Int.max) == 0
        }
        guard let top = windows.max(by: { windowRect($0).map { $0.width * $0.height } ?? 0
                                          < windowRect($1).map { $0.width * $0.height } ?? 0 }) else { return nil }
        return windowRect(top)
    }

    /// kCGWindowBounds always bridges as an NSDictionary of NSNumbers.
    private static func windowRect(_ window: [String: Any]) -> CGRect? {
        guard let ns = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
        func num(_ key: String) -> CGFloat? { (ns[key] as? NSNumber).map { CGFloat($0.doubleValue) } }
        if let x = num("X"), let y = num("Y"), let w = num("Width"), let h = num("Height") {
            return CGRect(x: x, y: y, width: w, height: h)
        }
        return nil
    }

    // MARK: - Private

    private static func mouseRect() -> CGRect {
        // NSEvent.mouseLocation is AppKit coords (origin bottom-left of primary screen).
        // Convert to CG coords (origin top-left).
        let mouse = NSEvent.mouseLocation
        let primaryH = NSScreen.screens.first?.frame.height ?? 800
        return CGRect(x: mouse.x - 10, y: primaryH - mouse.y - 10, width: 20, height: 20)
    }
}
