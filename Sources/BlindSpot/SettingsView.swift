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
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "BlindSpot Settings"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.minSize = NSSize(width: 720, height: 480)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            w.delegate = self
            window = w
        }
        CommandPanelController.shared.hide()
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
            Divider().opacity(0.4)
            contentPane
        }
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Traffic-light clearance
            Spacer().frame(height: 44)

            // App identity
            HStack(spacing: 7) {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("BlindSpot")
                    .font(.callout.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)

            // Nav items
            VStack(spacing: 1) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    sidebarButton(tab)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .frame(width: 176)
        .background(Color.primary.opacity(0.03))
    }

    private func sidebarButton(_ tab: SettingsTab) -> some View {
        Button { selectedTab = tab } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                Text(tab.rawValue)
                    .font(.callout)
                Spacer()
                if tab == .accessibility && !axGranted {
                    Circle().fill(.orange).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
    }

    // MARK: - Content pane

    @ViewBuilder
    private var contentPane: some View {
        if selectedTab == .profiles {
            // Profiles tab needs to fill the full height — no outer scroll
            VStack(spacing: 0) {
                Spacer().frame(height: 28)
                ProfilesTabView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Spacer().frame(height: 28)
                    switch selectedTab {
                    case .profiles:      EmptyView()
                    case .apiKeys:       allKeysSection
                    case .preferences:   globalSettingsSection
                    case .hotkeys:       hotkeysSection
                    case .accessibility: accessibilitySection
                    case .about:         versionSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

                Toggle(isOn: Binding(
                    get: { prefs.autoCopyLastResponse },
                    set: { prefs.setAutoCopyLastResponse($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-copy last response")
                            .font(.callout)
                        Text("Automatically copies the AI response to your clipboard as soon as streaming completes.")
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
                let granted = AXIsProcessTrusted()
                if granted { t.invalidate() }
                Task { @MainActor in axGranted = granted }
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
    let isSelected: Bool
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.callout)
                    .fontWeight(isSelected ? .medium : .regular)
                Text(profile.provider.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.12)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .contentShape(Rectangle())
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
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(profiles) { profile in
                            ProfileRow(
                                profile: profile,
                                isSelected: profile.id == selectedId,
                                isActive: profile.id == ProfilesStore.shared.activeProfileId
                            )
                            .onTapGesture { selectedId = profile.id }
                        }
                    }
                    .padding(6)
                }

                Divider().opacity(0.4)

                HStack(spacing: 2) {
                    Button(action: addProfile) {
                        Image(systemName: "plus")
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button(action: duplicateSelected) {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(selectedId == nil)

                    Spacer()

                    Button(action: deleteSelected) {
                        Image(systemName: "trash")
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedId == nil || profiles.count <= 1 ? Color.secondary : Color.red)
                    .disabled(selectedId == nil || profiles.count <= 1)
                }
                .padding(.horizontal, 6)
                .frame(height: 32)
            }
            .frame(width: 180)
            .background(Color.primary.opacity(0.03))

            Divider().opacity(0.4)

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
            VStack(alignment: .leading, spacing: 16) {

                // Name
                VStack(alignment: .leading, spacing: 5) {
                    fieldLabel("Name")
                    TextField("Profile name", text: $draft.name)
                        .textFieldStyle(.plain)
                        .glassField()
                        .onChange(of: draft.name) { _, _ in isDirty = true }
                }

                // Provider + Model
                VStack(alignment: .leading, spacing: 5) {
                    fieldLabel("Provider & Model")
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
                        .frame(width: 120)

                        TextField("Model identifier", text: $draft.model)
                            .textFieldStyle(.plain)
                            .glassField()
                            .onChange(of: draft.model) { _, _ in isDirty = true }
                    }
                }

                // System Prompt
                VStack(alignment: .leading, spacing: 5) {
                    fieldLabel("System Prompt")
                    PasteableTextEditor(text: $draft.systemPrompt)
                        .frame(height: 90)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .onChange(of: draft.systemPrompt) { _, _ in isDirty = true }
                }

                // Max output tokens + Temperature in one card
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            fieldLabel("Max Output Tokens")
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
                            in: 256...16384, step: 256
                        )
                    }

                    Divider().opacity(0.4)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            fieldLabel("Temperature")
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
                            in: 0.0...2.0, step: 0.1
                        )
                        Text("Lower = focused · Higher = creative")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

                // Actions
                HStack(spacing: 8) {
                    if isActiveProfile {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    } else {
                        Button("Set as Active") {
                            onActivate()
                            isActiveProfile = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Spacer()

                    if isDirty {
                        Button("Discard") {
                            if let stored = ProfilesStore.shared.profiles.first(where: { $0.id == draft.id }) {
                                draft = stored
                            }
                            isDirty = false
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    }

                    Button("Save") {
                        guard !draft.name.isEmpty, !draft.model.isEmpty else { return }
                        onSave(draft)
                        isDirty = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!isDirty)
                }
                .padding(.top, 4)
            }
            .padding(18)
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
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            content
        }
    }
}

// MARK: - Glass field style helper

private extension View {
    func glassField() -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private func fieldLabel(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
}
