import SwiftUI
import AppKit

/// NSViewRepresentable wrapper around NSTextField/NSSecureTextField.
/// Calls makeFirstResponder via viewDidMoveToWindow so paste works
/// immediately in .accessory-policy apps without any FocusState hacks.
struct PasteableKeyField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var isSecure: Bool

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isSecure ? AutoFocusSecureField() : AutoFocusPlainField()
        field.placeholderString = placeholder
        field.stringValue      = text
        field.bezelStyle       = .roundedBezel
        field.font             = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.delegate         = context.coordinator
        field.focusRingType    = .default
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }
        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            text = f.stringValue
        }
    }
}

// MARK: - Private subclasses that claim first responder on window attachment
//
// They also override performKeyEquivalent to handle Cmd+V/C/X/A/Z manually.
// BlindSpot runs as an .accessory app and never installs an application menu
// bar, so the standard Edit menu shortcuts (⌘V etc.) are never delivered to
// the field editor. Without this override, paste only works via right-click.

private class AutoFocusPlainField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        claimFocus()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleEditingKeyEquivalent(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

private class AutoFocusSecureField: NSSecureTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        claimFocus()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleEditingKeyEquivalent(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

private extension NSTextField {
    func claimFocus() {
        guard window != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }

    /// Routes Cmd+V/C/X/A/Z/Shift+Z to the responder chain so the field editor
    /// performs the standard editing action. Returns true if the event was
    /// handled.
    func handleEditingKeyEquivalent(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command) else { return false }
        // Only act when this field (or its field editor) is the first responder.
        guard let win = window, win.firstResponder === self || win.firstResponder === currentEditor() else {
            return false
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let action: Selector?
        switch key {
        case "v": action = #selector(NSText.paste(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "x": action = #selector(NSText.cut(_:))
        case "a": action = #selector(NSResponder.selectAll(_:))
        case "z": action = mods.contains(.shift)
            ? Selector(("redo:"))
            : Selector(("undo:"))
        default: return false
        }
        guard let sel = action else { return false }
        return NSApp.sendAction(sel, to: nil, from: self)
    }
}
