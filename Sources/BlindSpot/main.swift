import AppKit

let app = NSApplication.shared

// NSApplication.delegate is a *weak* reference. The delegate must stay alive
// for the lifetime of the process; if it's only held by a local variable
// inside a closure, ARC deallocates it as soon as the closure exits and
// callbacks like `applicationShouldTerminateAfterLastWindowClosed` are
// silently never invoked. Holding it at file scope keeps the strong ref.
let appDelegate: AppDelegate = MainActor.assumeIsolated { AppDelegate() }

MainActor.assumeIsolated {
    app.delegate = appDelegate
    app.setActivationPolicy(.accessory) // menu bar only, no dock icon, ever
}
app.run()
