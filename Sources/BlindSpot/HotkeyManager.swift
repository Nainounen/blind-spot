import AppKit

// Listens for the user-configured hotkey globally via CGEventTap.
// Requires Accessibility permission (System Settings > Privacy & Security > Accessibility).
class HotkeyManager {
    private var eventTap: CFMachPort?
    private let callback: () -> Void

    /// The currently-active hotkey. Mutable so SettingsView can change the
    /// binding at runtime without re-creating the event tap.
    private var keyCode: UInt16
    private var modifiers: UInt

    init(hotkey: Hotkey, callback: @escaping () -> Void) {
        self.callback = callback
        self.keyCode = hotkey.keyCode
        self.modifiers = hotkey.modifiers
    }

    /// Replace the active hotkey. Called from the main thread; the C tap
    /// callback reads these fields directly (also on the main run loop).
    func update(to hotkey: Hotkey) {
        keyCode = hotkey.keyCode
        modifiers = hotkey.modifiers
    }

    /// Temporarily disable the global tap so the Settings recorder can capture
    /// the user's keypress without us swallowing it first.
    func pause() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    func resume() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            print("[BlindSpot] Accessibility permission required — grant it in System Settings, then relaunch.")
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                // C function pointer — no captures allowed.
                guard let refcon else { return Unmanaged.passRetained(event) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

                guard mgr.modifiers != 0 else { return Unmanaged.passRetained(event) }

                let kc = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
                // 0xFFFF0000 == NSEvent.ModifierFlags.deviceIndependentFlagsMask.
                let masked = UInt(event.flags.rawValue) & 0xFFFF_0000

                if kc == mgr.keyCode && masked == mgr.modifiers {
                    DispatchQueue.main.async { mgr.callback() }
                    return nil // swallow
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            print("[BlindSpot] Failed to create event tap.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[BlindSpot] Listening for hotkey.")
    }

    deinit {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
    }
}
