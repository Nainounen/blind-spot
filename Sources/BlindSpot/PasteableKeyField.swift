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

private class AutoFocusPlainField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        claimFocus()
    }
}

private class AutoFocusSecureField: NSSecureTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        claimFocus()
    }
}

private extension NSTextField {
    func claimFocus() {
        guard window != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }
}
