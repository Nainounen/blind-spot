import AppKit

// Listens for Cmd+Shift+Space globally via CGEventTap.
// Requires Accessibility permission (System Settings > Privacy & Security > Accessibility).
class HotkeyManager {
    private var eventTap: CFMachPort?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
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
                guard let refcon else { return Unmanaged.passRetained(event) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let isSpace = keyCode == 49
                let isCmdShift = flags.contains(.maskCommand) && flags.contains(.maskShift)
                let noExtras = !flags.contains(.maskControl) && !flags.contains(.maskAlternate)

                if isSpace && isCmdShift && noExtras {
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
        print("[BlindSpot] Listening — press Cmd+Shift+Space over selected text.")
    }

    deinit {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
    }
}
