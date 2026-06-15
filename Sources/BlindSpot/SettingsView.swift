import SwiftUI
import AppKit

// MARK: - Settings tab

private enum SettingsTab: String, CaseIterable {
    case profiles      = "Profiles"
    case apiKeys       = "API Keys"
    case preferences   = "Preferences"
    case hotkeys       = "Hotkeys"
    case accessibility = "Accessibility"
    case about         = "About"

    var icon: String {
        switch self {
        case .profiles:      return "person.2.fill"
        case .apiKeys:       return "key.fill"
        case .preferences:   return "slider.horizontal.3"
        case .hotkeys:       return "keyboard"
        case .accessibility: return "figure.arms.open"
        case .about:         return "info.circle"
        }
    }
}

// MARK: - Window controller

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "BlindSpot Settings"
            w.minSize = NSSize(width: 760, height: 480)
            // Prevent AppKit from auto-releasing the window on close.
            // Without this, AppKit's internal release + our ARC release = double-free → crash.
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            w.delegate = self
            window = w
        }
        // Dismiss the command panel if it's open — it's distracting alongside Settings.
        CommandPanelController.shared.hide()
        // Show BlindSpot in Dock + App Switcher while Settings is open
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - View

@MainActor
struct SettingsView: View {
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var selectedTab: SettingsTab = .profiles
    @State private var editingKeyFor: Provider? = nil
    @State private var draftKey: String = ""
    @State private var showKey: Bool = false
    @State private var axGranted: Bool = AXIsProcessTrusted()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentPane
        }
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                sidebarButton(tab)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(width: 155)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func sidebarButton(_ tab: SettingsTab) -> some View {
        Button { selectedTab = tab } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .frame(width: 16)
                Text(tab.rawValue)
                Spacer()
                if tab == .accessibility && !axGranted {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
        .font(.callout)
    }

    // MARK: - Content pane

    @ViewBuilder
    private var contentPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch selectedTab {
                case .profiles:      ProfilesTabView()
                case .apiKeys:       allKeysSection
                case .preferences:   globalSettingsSection
                case .hotkeys:       hotkeysSection
                case .accessibility: accessibilitySection
                case .about:         versionSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - API Keys tab

    private var allKeysSection: some View {
        SettingsSection(title: "API Keys — All Providers") {
            VStack(spacing: 0) {
                let keyProviders = Provider.allCases.filter { $0.requiresKey }
                ForEach(Array(keyProviders.enumerated()), id: \.element.rawValue) { idx, provider in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(prefs.hasKey(for: provider) ? Color.green : Color.orange.opacity(0.8))
                            .frame(width: 7, height: 7)

                        Text(provider.displayName)
                            .frame(width: 96, alignment: .leading)
                            .font(.callout)

                        if provider == prefs.providerChoice {
                            Text("active")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.12), in: Capsule())
                        }

                        Spacer()

                        if prefs.hasKey(for: provider) {
                            Text("Key saved")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Change") {
                                draftKey = ""
                                showKey = false
                                editingKeyFor = provider
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            Button("Remove") { prefs.clearKey(for: provider) }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            if let url = provider.signupURL {
                                Link("Get key ↗", destination: URL(string: url)!)
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                                    .underline()
                            }
                            Button("Add") {
                                draftKey = ""
                                showKey = false
                                editingKeyFor = provider
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)

                    if idx < keyProviders.count - 1 {
                        Divider().padding(.leading, 27)
                    }
                }

                Divider().padding(.leading, 27)
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("Ollama")
                        .frame(width: 96, alignment: .leading)
                        .font(.callout)
                    if prefs.providerChoice == .ollama {
                        Text("active")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                    }
                    Spacer()
                    Text("Local — no key needed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
            }
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

            if editingKeyFor != nil {
                Divider()
                if let provider = editingKeyFor {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Edit key for \(provider.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        keyEditorView(for: provider)
                    }
                }
            }
        }
    }

    // MARK: - Settings tab

    private var globalSettingsSection: some View {
        SettingsSection(title: "Global Settings") {
            VStack(alignment: .leading, spacing: 12) {
                // Max tokens and system prompt moved to Profiles tab (per-profile).
                // These global settings are now managed in each AIProfile.

                Toggle(isOn: Binding(
                    get: { prefs.closeOnFocusLoss },
                    set: { prefs.setCloseOnFocusLoss($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Close panel when clicking outside")
                            .font(.callout)
                        Text("Raycast-style: the command panel hides automatically when you switch to another app. Off by default.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("System Prompt & Output Tokens")
                        .font(.callout)
                    Text("These are now configured per-profile in the Profiles tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Hotkeys tab

    private var hotkeysSection: some View {
        SettingsSection(title: "Hotkeys") {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trigger")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HotkeyRecorder(
                        hotkey: prefs.hotkey,
                        isRecording: Binding(
                            get: { prefs.isRecordingHotkey },
                            set: { prefs.isRecordingHotkey = $0 }
                        ),
                        onCapture: { prefs.setHotkey($0) }
                    )
                    if prefs.hotkey != .default {
                        Button("Reset to ⌘⇧Space") { prefs.resetHotkey() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Press over selected text")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Panic Quit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HotkeyRecorder(
                        hotkey: prefs.panicHotkey,
                        isRecording: Binding(
                            get: { prefs.isRecordingPanicHotkey },
                            set: { prefs.isRecordingPanicHotkey = $0 }
                        ),
                        onCapture: { prefs.setPanicHotkey($0) }
                    )
                    if prefs.panicHotkey != .defaultPanic {
                        Button("Reset to ⌘⌥Q") { prefs.resetPanicHotkey() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Force-quits instantly")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Accessibility tab

    private var accessibilitySection: some View {
        SettingsSection(title: "Accessibility") {
            if !axGranted {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility access required")
                            .font(.callout.bold())
                        Text("BlindSpot can't read selected text or listen for the hotkey until you grant access.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
            } else {
                HStack {
                    Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                }
                .font(.callout)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                Task { @MainActor in
                    axGranted = AXIsProcessTrusted()
                    if axGranted { t.invalidate() }
                }
            }
        }
    }

    // MARK: - About tab

    private var versionSection: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return SettingsSection(title: "About") {
            HStack {
                Text("BlindSpot \(version)")
                    .font(.callout)
                Spacer()
                Link("Release notes ↗", destination: URL(string: "https://github.com/Nainounen/blind-spot/releases/tag/v\(version)")!)
                    .font(.callout)
                    .foregroundStyle(Color.accentColor)
                    .underline()
            }
        }
    }

    // MARK: - Helpers

    private func keyEditorView(for provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PasteableKeyField(
                    placeholder: "Paste API key…",
                    text: $draftKey,
                    isSecure: !showKey
                )
                .id(showKey)
                .frame(height: 22)

                Button(showKey ? "Hide" : "Show") { showKey.toggle() }
                    .buttonStyle(.borderless)
            }
            HStack(spacing: 8) {
                Button("Save") {
                    prefs.saveKey(draftKey, for: provider)
                    editingKeyFor = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftKey.isEmpty)

                Button("Cancel") { editingKeyFor = nil }
                    .buttonStyle(.borderless)
            }
        }
    }

}

// MARK: - Native text editor (NSTextView wrapper)
// SwiftUI's TextEditor always renders a white NSTextView background on macOS
// regardless of scrollContentBackground(.hidden) — wrapping NSTextView directly
// lets us set drawsBackground = false on both the scroll view and text view.

private struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = .zero
        textView.drawsBackground = false
        textView.string = text
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
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

// MARK: - NSComboBox wrapper

private struct ModelComboBox: NSViewRepresentable {
    @Binding var text: String
    let suggestions: [String]
    let placeholder: String

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.isEditable = true
        box.completes = true
        box.numberOfVisibleItems = 8
        box.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        box.delegate = context.coordinator
        box.addItems(withObjectValues: suggestions)
        box.stringValue = text
        return box
    }

    func updateNSView(_ nsView: NSComboBox, context: Context) {
        let current = nsView.objectValues.compactMap { $0 as? String }
        if current != suggestions {
            nsView.removeAllItems()
            nsView.addItems(withObjectValues: suggestions)
        }
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }

        func controlTextDidChange(_ obj: Notification) {
            guard let box = obj.object as? NSComboBox else { return }
            text = box.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            if let selected = box.objectValueOfSelectedItem as? String {
                text = selected
            }
        }
    }
}

// MARK: - Profiles Tab

private struct ProfileRow: View {
    let profile: AIProfile
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.callout)
                Text(profile.provider.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption.bold())
            }
        }
        .padding(.vertical, 2)
    }
}

@MainActor
private struct ProfilesTabView: View {
    @State private var profiles: [AIProfile] = ProfilesStore.shared.profiles
    @State private var selectedId: UUID? = ProfilesStore.shared.activeProfileId
    @State private var draft: AIProfile? = nil

    private var selectedProfile: AIProfile? {
        guard let id = selectedId else { return nil }
        return profiles.first { $0.id == id }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Profile list
            VStack(spacing: 0) {
                List(selection: $selectedId) {
                    ForEach(Array(profiles)) { profile in
                        ProfileRow(profile: profile, isActive: profile.id == ProfilesStore.shared.activeProfileId)
                            .tag(profile.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack(spacing: 0) {
                    Button(action: addProfile) {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)

                    Button(action: duplicateSelected) {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedId == nil)

                    Spacer()

                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedId == nil || profiles.count <= 1)
                }
                .padding(.horizontal, 4)
                .frame(height: 32)
            }
            .frame(width: 180)

            Divider()

            // Profile editor
            if let d = draft {
                ProfileEditorView(draft: d, onSave: { updated in
                    ProfilesStore.shared.update(updated)
                    profiles = ProfilesStore.shared.profiles
                    draft = updated
                }, onActivate: {
                    ProfilesStore.shared.activate(d.id)
                    profiles = ProfilesStore.shared.profiles
                })
                .id(d.id)
            } else {
                VStack {
                    Spacer()
                    Text("Select a profile to edit")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedId) { _, newId in
            if let id = newId {
                draft = profiles.first { $0.id == id }
            }
        }
        .onAppear {
            profiles = ProfilesStore.shared.profiles
            if let id = selectedId, profiles.first(where: { $0.id == id }) != nil {
                draft = profiles.first { $0.id == id }
            } else if let first = profiles.first {
                selectedId = first.id
                draft = first
            }
        }
    }

    private func addProfile() {
        let new = AIProfile(name: "New Profile", provider: .openai)
        ProfilesStore.shared.create(new)
        profiles = ProfilesStore.shared.profiles
        selectedId = new.id
        draft = new
    }

    private func duplicateSelected() {
        guard let id = selectedId, let p = profiles.first(where: { $0.id == id }) else { return }
        ProfilesStore.shared.duplicate(p)
        profiles = ProfilesStore.shared.profiles
        if let copy = profiles.last { selectedId = copy.id; draft = copy }
    }

    private func deleteSelected() {
        guard let id = selectedId, profiles.count > 1 else { return }
        ProfilesStore.shared.delete(id)
        profiles = ProfilesStore.shared.profiles
        selectedId = profiles.first?.id
        draft = profiles.first
    }
}

@MainActor
private struct ProfileEditorView: View {
    @State var draft: AIProfile
    var onSave: (AIProfile) -> Void
    var onActivate: () -> Void

    @State private var isDirty: Bool = false
    @State private var isActiveProfile: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.caption.uppercaseSmallCaps())
                        .foregroundStyle(.secondary)
                    TextField("Profile name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: draft.name) { _, _ in isDirty = true }
                }

                // Provider + Model
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider & Model")
                        .font(.caption.uppercaseSmallCaps())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Picker("", selection: Binding(
                            get: { draft.provider },
                            set: { p in
                                draft.provider = p
                                draft.model = p.defaultModel
                                isDirty = true
                            }
                        )) {
                            ForEach(Provider.allCases, id: \.rawValue) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 130)

                        TextField("Model", text: $draft.model)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: draft.model) { _, _ in isDirty = true }
                    }
                }

                // System Prompt
                VStack(alignment: .leading, spacing: 6) {
                    Text("System Prompt")
                        .font(.caption.uppercaseSmallCaps())
                        .foregroundStyle(.secondary)
                    NativeTextEditor(text: $draft.systemPrompt)
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.12))
                        )
                        .onChange(of: draft.systemPrompt) { _, _ in isDirty = true }
                }

                // Max output tokens
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Max Output Tokens")
                            .font(.caption.uppercaseSmallCaps())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(draft.maxOutputTokens)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(draft.maxOutputTokens) },
                            set: { draft.maxOutputTokens = Int($0); isDirty = true }
                        ),
                        in: 256...16384,
                        step: 256
                    )
                }

                // Temperature
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Temperature")
                            .font(.caption.uppercaseSmallCaps())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", draft.temperature))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { draft.temperature },
                            set: { draft.temperature = $0; isDirty = true }
                        ),
                        in: 0.0...2.0,
                        step: 0.1
                    )
                    Text("Lower values are more focused; higher values are more creative.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                // Actions
                HStack(spacing: 10) {
                    if isActiveProfile {
                        Label("Active profile", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    } else {
                        Button("Set as Active") {
                            onActivate()
                            isActiveProfile = true
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    if isDirty {
                        Button("Discard") {
                            // Re-read from store to discard
                            if let stored = ProfilesStore.shared.profiles.first(where: { $0.id == draft.id }) {
                                draft = stored
                            }
                            isDirty = false
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    Button("Save") {
                        guard !draft.name.isEmpty, !draft.model.isEmpty else { return }
                        onSave(draft)
                        isDirty = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isDirty)
                }
            }
            .padding(20)
        }
        .onAppear {
            isActiveProfile = (draft.id == ProfilesStore.shared.activeProfileId)
        }
    }
}

// MARK: - Section layout

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.uppercaseSmallCaps())
                .foregroundStyle(.secondary)
            content
        }
    }
}
