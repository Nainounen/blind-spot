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
    static func captureRegion(_ rect: CGRect) async -> Data? {
        // Expand selection rect generously — 300px padding on each side gives
        // enough context for the AI to see surrounding UI, code, or layout.
        let padded = rect.insetBy(dx: -300, dy: -300)

        // Enforce a minimum capture size so even tiny selections (or the mouse
        // fallback) produce a useful screenshot.
        let minWidth: CGFloat  = 640
        let minHeight: CGFloat = 400
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

    // MARK: - Private

    private static func mouseRect() -> CGRect {
        // NSEvent.mouseLocation is AppKit coords (origin bottom-left of primary screen).
        // Convert to CG coords (origin top-left).
        let mouse = NSEvent.mouseLocation
        let primaryH = NSScreen.screens.first?.frame.height ?? 800
        return CGRect(x: mouse.x - 10, y: primaryH - mouse.y - 10, width: 20, height: 20)
    }
}
