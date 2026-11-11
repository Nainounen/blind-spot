import AppKit

// Listens for the user-configured hotkey globally via CGEventTap.
// Requires Accessibility permission (System Settings > Privacy & Security > Accessibility).
class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
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
        guard eventTap == nil else { return } // avoid a second tap + source on double-start
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            AutoAnswerLog.log("Accessibility NOT granted — hotkey tap disabled")
            print("[BlindSpot] Accessibility permission required — grant it in System Settings, then relaunch.")
            return
        }
        AutoAnswerLog.log("Accessibility granted — creating event tap")

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                // C function pointer — no captures allowed.
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

                guard mgr.modifiers != 0 else { return Unmanaged.passUnretained(event) }

                let kc = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
                // 0xFFFF0000 == NSEvent.ModifierFlags.deviceIndependentFlagsMask.
                // Caps Lock and the fn key sit inside that mask but toggle independently
                // of the user's chosen modifiers, so exclude them from BOTH sides.
                let transient = UInt(NSEvent.ModifierFlags.capsLock.rawValue)
                              | UInt(NSEvent.ModifierFlags.function.rawValue)
                let masked = (UInt(event.flags.rawValue) & 0xFFFF_0000) & ~transient

                if kc == mgr.keyCode && masked == (mgr.modifiers & ~transient) {
                    AutoAnswerLog.log("Hotkey fired: key=\(kc)")
                    DispatchQueue.main.async { mgr.callback() }
                    return nil // swallow
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            AutoAnswerLog.log("Failed to create event tap")
            print("[BlindSpot] Failed to create event tap.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        AutoAnswerLog.log("Event tap active (key=\(keyCode) mods=\(modifiers))")
        print("[BlindSpot] Listening for hotkey.")
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
}
