import SwiftUI
import AppKit

/// Multi-line text editor that handles Cmd+V/C/X/A/Z in .accessory-policy apps.
///
/// SwiftUI's TextEditor (NSTextView) doesn't receive key equivalents when the
/// app runs without a menu bar. This wraps NSTextView in a custom subclass that
/// overrides performKeyEquivalent — the same technique used in PasteableKeyField.
struct PasteableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    var minHeight: CGFloat = 110

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tv = EditingTextView()
        tv.delegate = context.coordinator
        tv.font = font
        tv.textColor = .labelColor
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.string = text

        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.documentView = tv

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak tv] in
            tv?.window?.makeFirstResponder(tv)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
        }
    }
}

private final class EditingTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command) else { return super.performKeyEquivalent(with: event) }

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let action: Selector?
        switch key {
        case "v": action = #selector(NSText.paste(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "x": action = #selector(NSText.cut(_:))
        case "a": action = #selector(NSResponder.selectAll(_:))
        case "z": action = mods.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
        default:  return super.performKeyEquivalent(with: event)
        }
        guard let sel = action else { return super.performKeyEquivalent(with: event) }
        return NSApp.sendAction(sel, to: nil, from: self)
    }
}
