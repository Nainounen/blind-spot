import SwiftUI
import AppKit

// MARK: - Window helper

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    // We deliberately do NOT switch activation policy to .regular while the
    // window is open. Doing so makes a Dock icon appear *and* makes AppKit
    // terminate the process when the last window closes, even with
    // applicationShouldTerminateAfterLastWindowClosed returning false.
    // Custom keyboard handling lives in PasteableKeyField, so we don't need
    // .regular for paste/typing to work.
    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "BlindSpot Settings"
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            w.delegate = self
            window = w
        }
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

// MARK: - View

@MainActor
struct SettingsView: View {
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var editingKeyFor: Provider? = nil
    @State private var draftKey: String = ""
    @State private var showKey: Bool = false
    @State private var draftModel: String = ""
    @State private var draftSystemPrompt: String = ""
    @State private var axGranted: Bool = AXIsProcessTrusted()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkle").foregroundStyle(.purple)
                Text("BlindSpot").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    activeProviderSection
                    Divider()
                    allKeysSection
                    Divider()
                    globalSettingsSection
                    Divider()
                    hotkeysSection
                    Divider()
                    accessibilitySection
                    Divider()
                    versionSection
                }
                .padding(24)
            }
        }
        .background(.ultraThickMaterial)
        .frame(width: 520)
        .onAppear {
            draftModel = prefs.currentModel(for: prefs.providerChoice)
            draftSystemPrompt = prefs.systemPrompt
            if prefs.providerChoice == .ollama {
                Task { @MainActor in
                    await prefs.refreshOllamaModels()
                    draftModel = prefs.currentModel(for: .ollama)
                }
            }
        }
    }

    // MARK: - Active Provider

    private var activeProviderSection: some View {
        SettingsSection(title: "Active Provider") {
            // Row 1: provider picker + model field
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { prefs.providerChoice },
                    set: { p in
                        prefs.setProvider(p)
                        draftModel = prefs.currentModel(for: p)
                        editingKeyFor = nil
                        if p == .ollama {
                            Task { @MainActor in
                                await prefs.refreshOllamaModels()
                                draftModel = prefs.currentModel(for: .ollama)
                            }
                        }
                    }
                )) {
                    ForEach(Provider.allCases, id: \.rawValue) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)

                if prefs.providerChoice == .ollama {
                    ollamaModelPicker
                } else {
                    ModelComboBox(
                        text: $draftModel,
                        suggestions: prefs.providerChoice.suggestedModels,
                        placeholder: prefs.providerChoice.defaultModel
                    )
                    .frame(height: 22)
                    .onChange(of: draftModel) { _, new in
                        prefs.setModel(new, for: prefs.providerChoice)
                    }
                    .onChange(of: prefs.providerChoice) { _, new in
                        draftModel = prefs.currentModel(for: new)
                    }
                }

                Button {
                    draftModel = prefs.providerChoice.defaultModel
                    prefs.setModel("", for: prefs.providerChoice)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Reset to default model")
            }

            // Row 2: API key for active provider
            if prefs.providerChoice.requiresKey {
                activeKeyRow
            } else {
                Label("No API key needed — Ollama runs locally.", systemImage: "laptopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var activeKeyRow: some View {
        let isEditing = editingKeyFor == prefs.providerChoice
        let hasKey = prefs.hasKey(for: prefs.providerChoice)

        if isEditing {
            keyEditorView(for: prefs.providerChoice)
        } else if hasKey {
            HStack(spacing: 10) {
                Label("Key saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                Spacer()
                Button("Change") {
                    draftKey = ""
                    showKey = false
                    editingKeyFor = prefs.providerChoice
                }
                .buttonStyle(.borderless)
                Button("Remove") { prefs.clearKey(for: prefs.providerChoice) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
            }
        } else {
            HStack(spacing: 10) {
                Label("No key set", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
                Spacer()
                if let url = prefs.providerChoice.signupURL {
                    Link("Get key →", destination: URL(string: url)!)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button("Add Key") {
                    draftKey = ""
                    showKey = false
                    editingKeyFor = prefs.providerChoice
                }
                .buttonStyle(.borderedProminent)
            }
        }

        Text("~/.config/blind-spot/keys/\(prefs.providerChoice.rawValue)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - All API Keys

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
                                if provider != prefs.providerChoice {
                                    prefs.setProvider(provider)
                                    draftModel = prefs.currentModel(for: provider)
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            Button("Remove") { prefs.clearKey(for: provider) }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            if let url = provider.signupURL {
                                Link("Get key", destination: URL(string: url)!)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button("Add") {
                                draftKey = ""
                                showKey = false
                                editingKeyFor = provider
                                if provider != prefs.providerChoice {
                                    prefs.setProvider(provider)
                                    draftModel = prefs.currentModel(for: provider)
                                }
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

                // Ollama row
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

        }
    }

    // MARK: - Global Settings

    private var globalSettingsSection: some View {
        SettingsSection(title: "Global Settings") {
            // Max tokens slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Max response length")
                        .font(.callout)
                    Spacer()
                    Text("\(prefs.maxTokens) tokens")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if prefs.maxTokens != 4096 {
                        Button("Reset") { prefs.setMaxTokens(4096) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Slider(
                    value: Binding(
                        get: { Double(prefs.maxTokens) },
                        set: { prefs.setMaxTokens(Int($0)) }
                    ),
                    in: 256...8192,
                    step: 256
                )
                .tint(.purple)

                HStack {
                    Text("256")
                    Spacer()
                    Text("1k")
                    Spacer()
                    Text("2k")
                    Spacer()
                    Text("4k")
                    Spacer()
                    Text("6k")
                    Spacer()
                    Text("8192")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                Text("Increase if responses get cut off mid-sentence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // System prompt
            VStack(alignment: .leading, spacing: 8) {
                Text("System Prompt")
                    .font(.callout.weight(.medium))

                NativeTextEditor(text: $draftSystemPrompt)
                    .frame(minHeight: 100, maxHeight: 180)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                HStack(alignment: .center, spacing: 8) {
                    Text("Sent to every request as the `system` message. Applied to all providers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if draftSystemPrompt != prefs.systemPrompt {
                        Button("Discard") { draftSystemPrompt = prefs.systemPrompt }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                    Button("Save") {
                        prefs.saveSystemPrompt(
                            draftSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftSystemPrompt == prefs.systemPrompt)
                }

                Text("~/.config/blind-spot/system-prompt.txt")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Hotkeys

    private var hotkeysSection: some View {
        SettingsSection(title: "Hotkeys") {
            HStack(alignment: .top, spacing: 24) {
                // Trigger hotkey
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

                // Panic hotkey
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

    // MARK: - Accessibility

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

    // MARK: - About

    private var versionSection: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return SettingsSection(title: "About") {
            HStack {
                Text("BlindSpot \(version)")
                    .font(.callout)
                Spacer()
                Link("Release notes", destination: URL(string: "https://github.com/Nainounen/blind-spot/releases/tag/v\(version)")!)
                    .font(.callout)
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

    @ViewBuilder
    private var ollamaModelPicker: some View {
        if prefs.installedOllamaModels.isEmpty {
            TextField(prefs.providerChoice.defaultModel, text: $draftModel)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onChange(of: draftModel) { _, new in prefs.setModel(new, for: .ollama) }
        } else {
            Picker("", selection: $draftModel) {
                ForEach(prefs.installedOllamaModels, id: \.self) { name in
                    Text(name).tag(name)
                }
                if !prefs.installedOllamaModels.contains(draftModel) && !draftModel.isEmpty {
                    Text("\(draftModel) (custom)").tag(draftModel)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: draftModel) { _, new in prefs.setModel(new, for: .ollama) }
        }

        Button {
            Task { @MainActor in
                await prefs.refreshOllamaModels()
                draftModel = prefs.currentModel(for: .ollama)
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Refresh installed Ollama models")
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
