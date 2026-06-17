import SwiftUI
import AppKit

// MARK: - Markdown rendering (shared with overlay)

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

        if stripped.isEmpty { i += 1; continue }

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

// MARK: - Conversation sidebar

private enum ConversationGroup: String {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "This Week"
    case earlier = "Earlier"
}

private func groupConversations(_ convs: [Conversation]) -> [(ConversationGroup, [Conversation])] {
    let cal = Calendar.current
    let now = Date()
    var today: [Conversation] = []
    var yesterday: [Conversation] = []
    var thisWeek: [Conversation] = []
    var earlier: [Conversation] = []

    for c in convs {
        if cal.isDateInToday(c.updatedAt) {
            today.append(c)
        } else if cal.isDateInYesterday(c.updatedAt) {
            yesterday.append(c)
        } else if let days = cal.dateComponents([.day], from: c.updatedAt, to: now).day, days < 7 {
            thisWeek.append(c)
        } else {
            earlier.append(c)
        }
    }

    return [(.today, today), (.yesterday, yesterday), (.thisWeek, thisWeek), (.earlier, earlier)]
        .filter { !$1.isEmpty }
}

private func relativeTime(_ date: Date) -> String {
    let diff = Date().timeIntervalSince(date)
    if diff < 60 { return "Just now" }
    if diff < 3600 { return "\(Int(diff / 60))m ago" }
    if diff < 86400 { return "\(Int(diff / 3600))h ago" }
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f.string(from: date)
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let folders: [Folder]
    var onDelete: () -> Void
    var onSelect: () -> Void

    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title.isEmpty ? "New conversation" : conversation.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(relativeTime(conversation.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete conversation")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.15)
                : isHovered ? Color.primary.opacity(0.04) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
        .contextMenu {
            Menu("Export") {
                Button("Export as Markdown") {
                    exportConversation(conversation, format: .markdown)
                }
                Button("Export as JSON") {
                    exportConversation(conversation, format: .json)
                }
            }

            if !folders.isEmpty || conversation.folderId != nil {
                Divider()
                Menu("Move to Folder") {
                    if conversation.folderId != nil {
                        Button("Remove from Folder") {
                            ConversationStore.shared.moveConversation(conversation.id, toFolder: nil)
                        }
                        Divider()
                    }
                    ForEach(folders.filter { $0.id != conversation.folderId }) { folder in
                        Button(folder.name) {
                            ConversationStore.shared.moveConversation(conversation.id, toFolder: folder.id)
                        }
                    }
                }
            }

            Divider()
            Button("Delete", role: .destructive) { showDeleteConfirm = true }
        }
        .confirmationDialog("Delete this conversation?", isPresented: $showDeleteConfirm) {
            // No .destructive role so macOS makes this the default button (Enter triggers it)
            Button("Delete") { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

@MainActor
private struct FolderSection: View {
    let folder: Folder
    let conversations: [Conversation]
    let allFolders: [Folder]
    let activeConvId: UUID?
    var onSelect: (Conversation) -> Void
    var onDelete: (UUID) -> Void

    @State private var isExpanded = true
    @State private var isRenaming = false
    @State private var renameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                Image(systemName: "folder.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Text(folder.name)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(conversations.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() }
            }
            .contextMenu {
                Button("Rename Folder") { renameDraft = folder.name; isRenaming = true }
                if !conversations.isEmpty {
                    Divider()
                    Menu("Export Folder") {
                        Button("Export as Markdown") {
                            exportFolder(folder, conversations: conversations, format: .markdown)
                        }
                        Button("Export as JSON") {
                            exportFolder(folder, conversations: conversations, format: .json)
                        }
                    }
                }
                Divider()
                Button("Delete Folder", role: .destructive) {
                    ConversationStore.shared.deleteFolder(folder.id)
                }
            }

            if isExpanded {
                ForEach(conversations) { conv in
                    ConversationRow(
                        conversation: conv,
                        isSelected: activeConvId == conv.id,
                        folders: allFolders,
                        onDelete: { onDelete(conv.id) },
                        onSelect: { onSelect(conv) }
                    )
                    .padding(.horizontal, 6)
                    .padding(.leading, 6)
                }
            }
        }
        .alert("Rename Folder", isPresented: $isRenaming) {
            TextField("Folder name", text: $renameDraft)
            Button("Rename") {
                if !renameDraft.isEmpty {
                    ConversationStore.shared.renameFolder(folder.id, to: renameDraft)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

@MainActor
private struct SidebarView: View {
    @Bindable var vm: CommandPanelViewModel
    let conversations: [Conversation]
    let folders: [Folder]
    var onSelect: (Conversation) -> Void
    var onNew: () -> Void
    var onDelete: (UUID) -> Void

    @FocusState private var searchFocused: Bool
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search", text: $vm.sidebarSearch)
                    .font(.callout)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !vm.sidebarSearch.isEmpty {
                    Button(action: { vm.sidebarSearch = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Conversation list
            if conversations.isEmpty && folders.isEmpty {
                emptyState
            } else if !vm.sidebarSearch.isEmpty {
                searchResults
            } else {
                mainList
            }

            Divider()

            // Bottom toolbar
            HStack(spacing: 0) {
                Button(action: onNew) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.caption.bold())
                        Text("New").font(.callout)
                        Spacer()
                        Text("⌘N").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    newFolderName = ""
                    showNewFolderAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Folder")
                .padding(.trailing, 4)
            }
        }
        .onChange(of: vm.focusSidebarSearch) { _, newVal in
            if newVal { searchFocused = true; vm.focusSidebarSearch = false }
        }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                if !newFolderName.isEmpty {
                    ConversationStore.shared.createFolder(name: newFolderName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - List sections

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No conversations yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
    }

    private var searchResults: some View {
        let q = vm.sidebarSearch.lowercased()
        let results = conversations.filter { $0.title.lowercased().contains(q) }
        return Group {
            if results.isEmpty {
                VStack { Spacer(); Text("No results").font(.caption).foregroundStyle(.secondary); Spacer() }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { conv in
                            ConversationRow(
                                conversation: conv,
                                isSelected: vm.activeConversation?.id == conv.id,
                                folders: folders,
                                onDelete: { onDelete(conv.id) },
                                onSelect: { onSelect(conv) }
                            )
                            .padding(.horizontal, 6)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var mainList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Folders
                if !folders.isEmpty {
                    ForEach(folders) { folder in
                        FolderSection(
                            folder: folder,
                            conversations: ConversationStore.shared.conversations(inFolder: folder.id),
                            allFolders: folders,
                            activeConvId: vm.activeConversation?.id,
                            onSelect: onSelect,
                            onDelete: onDelete
                        )
                    }

                    if !ConversationStore.shared.unfolderedConversations.isEmpty {
                        Divider()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                }

                // Unfoldered conversations grouped by date
                ForEach(groupConversations(ConversationStore.shared.unfolderedConversations), id: \.0.rawValue) { group, items in
                    Text(group.rawValue)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 2)

                    ForEach(items) { conv in
                        ConversationRow(
                            conversation: conv,
                            isSelected: vm.activeConversation?.id == conv.id,
                            folders: folders,
                            onDelete: { onDelete(conv.id) },
                            onSelect: { onSelect(conv) }
                        )
                        .padding(.horizontal, 6)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Main conversation area

private struct TurnView: View {
    let turn: CommandPanelViewModel.Turn
    let isLast: Bool
    let isLoading: Bool
    let errorMessage: String?
    let isFirst: Bool

    @State private var isHovered = false
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // User query bubble
            if !turn.query.isEmpty {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        if turn.hasImage {
                            Label("Image attached", systemImage: "photo")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(turn.query)
                            .font(.callout)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)
                }
            }

            // Response
            if isLast && isLoading && turn.response.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Thinking…").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            } else if isLast, let err = errorMessage, turn.response.isEmpty {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if !turn.response.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    MarkdownView(text: turn.response)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(turn.response, forType: .string)
                            isCopied = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                isCopied = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .font(.caption2)
                                if isHovered {
                                    Text(isCopied ? "Copied" : "Copy")
                                        .font(.caption2)
                                }
                            }
                            .foregroundStyle(isCopied ? .green : .secondary)
                            .padding(.horizontal, isHovered ? 8 : 5)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(isHovered ? 0.06 : 0.04), in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help("Copy response")
                        .animation(.easeInOut(duration: 0.12), value: isHovered)
                    }
                }
            }
        }
        .onHover { isHovered = $0 }
    }
}

@MainActor
private struct ConversationArea: View {
    @Bindable var vm: CommandPanelViewModel
    var onFollowUp: (String) -> Void
    var onCancel: () -> Void
    var onClose: () -> Void
    var isCompact: Bool = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        let hasContent = !vm.turns.isEmpty || vm.isLoading
        if isCompact && !hasContent {
            // XS empty: just the input bar, vertically centered
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                inputBar
                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 0) {
                if hasContent {
                    conversationScroll
                } else {
                    emptyState
                }
                Divider()
                inputBar
            }
        }
    }

    private var conversationScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(vm.turns.enumerated()), id: \.offset) { idx, turn in
                        TurnView(
                            turn: turn,
                            isLast: idx == vm.turns.count - 1,
                            isLoading: vm.isLoading,
                            errorMessage: vm.errorMessage,
                            isFirst: idx == 0
                        )
                        if idx < vm.turns.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }

                    if vm.turns.isEmpty && vm.isLoading {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text("Thinking…").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(isCompact ? 12 : 16)
                .padding(.bottom, 8)

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
    }

    private var inputBar: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $vm.followUpText)
                    .font(.system(size: 13))
                    .frame(height: followUpHeight)
                    .scrollContentBackground(.hidden)
                    .focused($inputFocused)
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        if press.modifiers.contains(.shift) { return .ignored }
                        submit()
                        return .handled
                    }
                    .onChange(of: vm.focusInput) { _, newValue in
                        if newValue {
                            inputFocused = true
                            vm.focusInput = false
                        }
                    }

                if vm.followUpText.isEmpty {
                    Text(vm.turns.isEmpty ? "Ask anything…" : "Ask a follow-up…")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
            }

            if vm.isLoading {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Stop generating (Ctrl+C)")
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(
                            vm.followUpText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.secondary : Color.accentColor
                        )
                }
                .buttonStyle(.plain)
                .disabled(vm.followUpText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var followUpHeight: CGFloat {
        let lines = vm.followUpText.components(separatedBy: "\n").count
        let lineH: CGFloat = 19
        return min(CGFloat(lines) * lineH + 14, 5 * lineH + 14)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkle")
                .font(.largeTitle)
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Ask anything")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Select text anywhere and press the hotkey,\nor type below for a free-form question.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        let text = vm.followUpText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !vm.isLoading else { return }
        vm.followUpText = ""
        onFollowUp(text)
    }
}

// MARK: - Bottom status bar

private struct StatusBar: View {
    var onClose: () -> Void

    var body: some View {
        let active = ProfilesStore.shared.activeProfile
        let all = ProfilesStore.shared.profiles

        HStack(spacing: 8) {
            if all.count > 1 {
                Menu {
                    ForEach(all) { p in
                        Button {
                            ProfilesStore.shared.activate(p.id)
                        } label: {
                            HStack {
                                Text(p.name)
                                if p.id == ProfilesStore.shared.activeProfileId {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(providerColor(active.provider))
                            .frame(width: 7, height: 7)
                        Text(active.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                HStack(spacing: 5) {
                    Circle()
                        .fill(providerColor(active.provider))
                        .frame(width: 7, height: 7)
                    Text(active.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Text("ESC")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
            Text("to close")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func providerColor(_ p: Provider) -> Color {
        switch p {
        case .openai:     return .green
        case .anthropic:  return .orange
        case .gemini:     return .blue
        case .deepseek:   return .cyan
        case .grok:       return .primary
        case .openrouter: return .purple
        case .ollama:     return .indigo
        }
    }
}

// MARK: - Root panel view

struct CommandPanelView: View {
    @Bindable var vm: CommandPanelViewModel
    var onClose: () -> Void
    var onFollowUp: (String) -> Void
    var onSelectConversation: (Conversation) -> Void
    var onNewConversation: () -> Void
    var onCancel: () -> Void

    @State private var conversations: [Conversation] = []
    @State private var folders: [Folder] = []
    @ObservedObject private var prefs = PreferencesStore.shared

    private let sidebarWidth: CGFloat = 200

    var body: some View {
        Group {
            if prefs.panelSizePreset == .xs {
                xsLayout
            } else {
                standardLayout
            }
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .conversationsDidUpdate)) { _ in
            reload()
        }
    }

    // MARK: - XS compact layout (minimal header, no sidebar)

    private var xsLayout: some View {
        let active = ProfilesStore.shared.activeProfile
        let all = ProfilesStore.shared.profiles

        return VStack(spacing: 0) {
            // Minimal header: profile switcher + close button
            HStack {
                if all.count > 1 {
                    Menu {
                        ForEach(all) { p in
                            Button {
                                ProfilesStore.shared.activate(p.id)
                            } label: {
                                HStack {
                                    Text(p.name)
                                    if p.id == ProfilesStore.shared.activeProfileId {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(providerColor(active.provider))
                                .frame(width: 6, height: 6)
                            Text(active.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(providerColor(active.provider))
                            .frame(width: 6, height: 6)
                        Text(active.name)
                            .font(.caption)
                    }
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            ConversationArea(
                vm: vm,
                onFollowUp: onFollowUp,
                onCancel: onCancel,
                onClose: onClose,
                isCompact: true
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Standard layout (sidebar + conversation + status bar)

    private var standardLayout: some View {
        HStack(spacing: 0) {
            SidebarView(
                vm: vm,
                conversations: conversations,
                folders: folders,
                onSelect: onSelectConversation,
                onNew: onNewConversation,
                onDelete: { id in
                    ConversationStore.shared.delete(id)
                    if vm.activeConversation?.id == id {
                        vm.startNewConversation(profileId: ProfilesStore.shared.activeProfile.id)
                    }
                }
            )
            .frame(width: sidebarWidth)
            .background(Color.primary.opacity(0.03))

            Divider()

            VStack(spacing: 0) {
                ConversationArea(
                    vm: vm,
                    onFollowUp: onFollowUp,
                    onCancel: onCancel,
                    onClose: onClose
                )
                Divider()
                StatusBar(onClose: onClose)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @MainActor private func reload() {
        conversations = ConversationStore.shared.conversations
        folders = ConversationStore.shared.folders
    }

    private func providerColor(_ p: Provider) -> Color {
        switch p {
        case .openai:     return .green
        case .anthropic:  return .orange
        case .gemini:     return .blue
        case .deepseek:   return .cyan
        case .grok:       return .primary
        case .openrouter: return .purple
        case .ollama:     return .indigo
        }
    }
}
