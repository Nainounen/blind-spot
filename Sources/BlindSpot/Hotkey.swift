import AppKit

/// Persisted, user-configurable hotkey.
///
/// `modifiers` stores the raw bitmask of `NSEvent.ModifierFlags` already masked
/// to `deviceIndependentFlagsMask`. The same bit layout is also valid for
/// `CGEventFlags`, so the global event tap can compare directly without
/// converting.
struct Hotkey: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt

    static let `default` = Hotkey(
        keyCode: 49, // Space
        modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue
    )

    static let defaultPanic = Hotkey(
        keyCode: 12, // Q
        modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue
    )

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }
}

extension Hotkey {
    /// Modifier glyphs followed by the key name, in standard macOS order.
    var displaySymbols: [String] {
        var parts: [String] = []
        let m = modifierFlags
        if m.contains(.control) { parts.append("⌃") }
        if m.contains(.option)  { parts.append("⌥") }
        if m.contains(.shift)   { parts.append("⇧") }
        if m.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts
    }

    var displayString: String { displaySymbols.joined() }

    /// Best-effort mapping of common macOS virtual key codes to a label.
    static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case 0:   return "A"
        case 1:   return "S"
        case 2:   return "D"
        case 3:   return "F"
        case 4:   return "H"
        case 5:   return "G"
        case 6:   return "Z"
        case 7:   return "X"
        case 8:   return "C"
        case 9:   return "V"
        case 11:  return "B"
        case 12:  return "Q"
        case 13:  return "W"
        case 14:  return "E"
        case 15:  return "R"
        case 16:  return "Y"
        case 17:  return "T"
        case 18:  return "1"
        case 19:  return "2"
        case 20:  return "3"
        case 21:  return "4"
        case 22:  return "6"
        case 23:  return "5"
        case 24:  return "="
        case 25:  return "9"
        case 26:  return "7"
        case 27:  return "-"
        case 28:  return "8"
        case 29:  return "0"
        case 30:  return "]"
        case 31:  return "O"
        case 32:  return "U"
        case 33:  return "["
        case 34:  return "I"
        case 35:  return "P"
        case 36:  return "Return"
        case 37:  return "L"
        case 38:  return "J"
        case 39:  return "'"
        case 40:  return "K"
        case 41:  return ";"
        case 42:  return "\\"
        case 43:  return ","
        case 44:  return "/"
        case 45:  return "N"
        case 46:  return "M"
        case 47:  return "."
        case 48:  return "⇥"
        case 49:  return "Space"
        case 50:  return "`"
        case 51:  return "⌫"
        case 53:  return "Esc"
        case 76:  return "↩︎"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 99:  return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 109: return "F10"
        case 111: return "F12"
        case 115: return "Home"
        case 116: return "Page Up"
        case 117: return "⌦"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "Page Down"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:  return "Key \(keyCode)"
        }
    }
}
