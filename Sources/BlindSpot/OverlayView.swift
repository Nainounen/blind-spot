import SwiftUI
import AppKit
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

        if line.hasPrefix("#") {
            let level = line.prefix(while: { $0 == "#" }).count
            let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
            blocks.append(.heading(level: min(level, 3), text: text))
            i += 1
            continue
        }

        let stripped = line.trimmingCharacters(in: .whitespaces)
        if stripped == "---" || stripped == "***" || stripped == "___" {
            blocks.append(.divider)
            i += 1
            continue
        }

        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            blocks.append(.bulletItem(String(line.dropFirst(2))))
            i += 1
            continue
        }

        if stripped.isEmpty {
            i += 1
            continue
        }

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
    struct Turn {
        let query: String
        var response: String
    }

    var turns: [Turn] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var followUpText: String = ""
    var isCopied: Bool = false

    var latestResponse: String { turns.last?.response ?? "" }
}

// MARK: - Overlay

struct OverlayView: View {
    @Bindable var vm: OverlayViewModel
    var onClose: () -> Void
    var onFollowUp: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(vm.turns.enumerated()), id: \.offset) { index, turn in
                            if !turn.query.isEmpty {
                                queryBox(turn.query, isFirst: index == 0)
                            }
                            responseBox(turn, isLast: index == vm.turns.count - 1)
                            if index < vm.turns.count - 1 {
                                Divider()
                            }
                        }

                        if vm.turns.isEmpty && vm.isLoading {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.75)
                                Text("Thinking…").foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.bottom, 4)

                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: vm.turns.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: vm.turns.last?.response) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            followUpBar
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "sparkle").foregroundStyle(.purple)
            Text("BlindSpot").font(.headline)
            Spacer()
            if !vm.latestResponse.isEmpty {
                Button(action: copyResponse) {
                    Image(systemName: vm.isCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(vm.isCopied ? .green : .secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private func copyResponse() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(vm.latestResponse, forType: .string)
        vm.isCopied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            vm.isCopied = false
        }
    }

    // MARK: - Turn sub-views

    private func queryBox(_ query: String, isFirst: Bool) -> some View {
        GroupBox {
            Text(query)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(4)
                .truncationMode(.tail)
        } label: {
            Label(isFirst ? "Selected text" : "Follow-up", systemImage: isFirst ? "text.cursor" : "bubble.left")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func responseBox(_ turn: OverlayViewModel.Turn, isLast: Bool) -> some View {
        GroupBox {
            Group {
                if isLast && vm.isLoading && turn.response.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.75)
                        Text("Thinking…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if isLast, let err = vm.errorMessage, turn.response.isEmpty {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                } else {
                    MarkdownView(text: turn.response)
                        .textSelection(.enabled)
                        .padding(.vertical, 2)
                }
            }
        } label: {
            Label("Response", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Follow-up bar

    private var followUpBar: some View {
        HStack(spacing: 8) {
            PasteableKeyField(
                placeholder: "Ask a follow-up…",
                text: $vm.followUpText,
                isSecure: false,
                autoFocus: false,
                onSubmit: submitFollowUp
            )
            .frame(height: 22)

            Button("Send", action: submitFollowUp)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(vm.followUpText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isLoading)
        }
    }

    private func submitFollowUp() {
        let text = vm.followUpText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !vm.isLoading else { return }
        vm.followUpText = ""
        onFollowUp(text)
    }
}
