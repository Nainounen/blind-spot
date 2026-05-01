import SwiftUI
import AppKit

/// NSViewRepresentable wrapper around NSTextField/NSSecureTextField.
/// Handles Cmd+V/C/X/A/Z in .accessory-policy apps (no application menu bar).
///
/// - `autoFocus`: when true, claims first-responder as soon as the view enters
///   a window (used in Settings and Onboarding). Set false for inline fields
///   like the overlay follow-up bar where the user reads first, types later.
/// - `onSubmit`: called when the user presses Return.
struct PasteableKeyField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var isSecure: Bool
    var autoFocus: Bool = true
    var onSubmit: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField
        if isSecure {
            field = autoFocus ? AutoFocusSecureField() : PlainSecureField()
        } else {
            field = autoFocus ? AutoFocusPlainField() : PlainTextField()
        }
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
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onSubmit: onSubmit) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onSubmit: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            _text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            text = f.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit?()
                return true
            }
            return false
        }
    }
}

// MARK: - Auto-focusing variants (Settings / Onboarding)

private class AutoFocusPlainField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        claimFocus()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditingShortcut(event) || super.performKeyEquivalent(with: event)
    }
}

private class AutoFocusSecureField: NSSecureTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        claimFocus()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditingShortcut(event) || super.performKeyEquivalent(with: event)
    }
}

// MARK: - Non-auto-focusing variants (overlay follow-up bar)

private class PlainTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditingShortcut(event) || super.performKeyEquivalent(with: event)
    }
}

private class PlainSecureField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditingShortcut(event) || super.performKeyEquivalent(with: event)
    }
}

// MARK: - Shared helpers

private extension NSTextField {
    func claimFocus() {
        guard window != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }

    /// Routes Cmd+V/C/X/A/Z/Shift+Z to the responder chain.
    func handleEditingShortcut(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command) else { return false }
        guard let win = window,
              win.firstResponder === self || win.firstResponder === currentEditor()
        else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let action: Selector?
        switch key {
        case "v": action = #selector(NSText.paste(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "x": action = #selector(NSText.cut(_:))
        case "a": action = #selector(NSResponder.selectAll(_:))
        case "z": action = mods.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
        default:  return false
        }
        return NSApp.sendAction(action!, to: nil, from: self)
    }
}
