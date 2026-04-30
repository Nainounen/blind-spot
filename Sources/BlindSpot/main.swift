import AppKit

let app = NSApplication.shared
// Main thread is guaranteed before app.run() — use assumeIsolated to satisfy
// the Swift concurrency checker for @MainActor-isolated types.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu bar only, no dock icon
}
app.run()
