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
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        let tv = EditingTextView()
        tv.delegate = context.coordinator
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        // usesAdaptiveColorMappingForDarkAppearance is the correct Apple API
        // for NSTextViews with drawsBackground=false inside material/vibrancy
        // containers. Without it, NSTextView can't resolve dynamic colors
        // (textColor, insertion point) against the correct appearance context.
        tv.usesAdaptiveColorMappingForDarkAppearance = true
        tv.textContainerInset = NSSize(width: 6, height: 6)
        // NSColor.textColor is the semantic color for editable text fields;
        // .labelColor is for static labels and should not be used here.
        tv.textColor = .textColor
        tv.insertionPointColor = .textColor
        tv.typingAttributes = textAttributes
        setAttributedText(tv, to: text)

        scrollView.documentView = tv

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak tv] in
            tv?.window?.makeFirstResponder(tv)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        if tv.string != text { setAttributedText(tv, to: text) }
        tv.typingAttributes = textAttributes
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.textColor]
    }

    private func setAttributedText(_ tv: NSTextView, to string: String) {
        tv.textStorage?.setAttributedString(NSAttributedString(string: string, attributes: textAttributes))
        tv.typingAttributes = textAttributes
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
        switch key {
        case "v": paste(nil);      return true
        case "c": copy(nil);       return true
        case "x": cut(nil);        return true
        case "a": selectAll(nil);  return true
        case "z":
            if mods.contains(.shift) { undoManager?.redo() }
            else                     { undoManager?.undo() }
            return true
        default:  return super.performKeyEquivalent(with: event)
        }
    }
}
