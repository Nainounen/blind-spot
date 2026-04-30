import SwiftUI
import Foundation

// MARK: - Markdown block renderer

private enum MDBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletItem(String)
    case codeBlock(String)
    case divider
}

private func parseBlocks(_ raw: String) -> [MDBlock] {
    var blocks: [MDBlock] = []
    let lines = raw.components(separatedBy: "\n")
    var i = 0

    while i < lines.count {
        let line = lines[i]

        // Code block
        if line.hasPrefix("```") {
            var code: [String] = []
            i += 1
            while i < lines.count && !lines[i].hasPrefix("```") {
                code.append(lines[i])
                i += 1
            }
            blocks.append(.codeBlock(code.joined(separator: "\n")))
            i += 1
            continue
        }

        // Heading
        if line.hasPrefix("#") {
            let level = line.prefix(while: { $0 == "#" }).count
            let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
            blocks.append(.heading(level: min(level, 3), text: text))
            i += 1
            continue
        }

        // Horizontal rule
        let stripped = line.trimmingCharacters(in: .whitespaces)
        if stripped == "---" || stripped == "***" || stripped == "___" {
            blocks.append(.divider)
            i += 1
            continue
        }

        // Bullet list item
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            let text = String(line.dropFirst(2))
            blocks.append(.bulletItem(text))
            i += 1
            continue
        }

        // Empty line — skip
        if stripped.isEmpty {
            i += 1
            continue
        }

        // Paragraph: collect consecutive non-special lines
        var para: [String] = [line]
        i += 1
        while i < lines.count {
            let next = lines[i]
            let ns = next.trimmingCharacters(in: .whitespaces)
            if ns.isEmpty || next.hasPrefix("#") || next.hasPrefix("```")
                || next.hasPrefix("- ") || next.hasPrefix("* ") || next.hasPrefix("• ")
                || ns == "---" { break }
            para.append(next)
            i += 1
        }
        blocks.append(.paragraph(para.joined(separator: " ")))
    }

    return blocks
}

private func inlineText(_ raw: String) -> Text {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    if let attr = try? AttributedString(markdown: raw, options: options) {
        return Text(attr)
    }
    return Text(raw)
}

private struct MDBlockView: View {
    let block: MDBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(level == 1 ? .title2.bold() : level == 2 ? .headline : .subheadline.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level == 1 ? 6 : 2)

        case .paragraph(let text):
            inlineText(text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

        case .bulletItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").font(.callout).foregroundStyle(.secondary)
                inlineText(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .codeBlock(let code):
            Text(code)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)

        case .divider:
            Divider()
        }
    }
}

private struct MarkdownView: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                MDBlockView(block: block)
            }
        }
    }
}

// MARK: - View model

@Observable
class OverlayViewModel {
    var query: String = ""
    var response: String = ""
    var isLoading: Bool = false
    var errorMessage: String? = nil
}

// MARK: - Overlay

struct OverlayView: View {
    var vm: OverlayViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !vm.query.isEmpty { queryBox }
            responseBox
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 320)
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkle")
                .foregroundStyle(.purple)
            Text("Blind Spot")
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var queryBox: some View {
        GroupBox {
            Text(vm.query)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(4)
                .truncationMode(.tail)
        } label: {
            Label("Selected text", systemImage: "text.cursor")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var responseBox: some View {
        GroupBox {
            Group {
                if vm.isLoading && vm.response.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.75)
                        Text("Thinking…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let err = vm.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                } else {
                    ScrollView {
                        MarkdownView(text: vm.response)
                            .textSelection(.enabled)
                            .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        } label: {
            Label("Response", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
}
