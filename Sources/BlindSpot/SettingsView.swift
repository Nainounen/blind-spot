import SwiftUI
import AppKit

// MARK: - Window helper

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
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
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - View

struct SettingsView: View {
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var editingKey: Provider? = nil
    @State private var draftKey: String = ""
    @State private var showKey: Bool = false
    @State private var draftModel: String = ""
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
                    providerSection
                    Divider()
                    apiKeySection
                    Divider()
                    modelSection
                    Divider()
                    accessibilitySection
                    Divider()
                    hotkeySection
                }
                .padding(24)
            }
        }
        .background(.ultraThickMaterial)
        .frame(width: 520)
        .onAppear {
            draftModel = prefs.currentModel(for: prefs.providerChoice)
            if prefs.providerChoice == .ollama {
                Task { @MainActor in
                    await prefs.refreshOllamaModels()
                    draftModel = prefs.currentModel(for: .ollama)
                }
            }
        }
    }

    // MARK: - Sections

    private var providerSection: some View {
        SettingsSection(title: "AI Provider") {
            Picker("Provider", selection: Binding(
                get: { prefs.providerChoice },
                set: { prefs.setProvider($0); draftModel = prefs.currentModel(for: $0) }
            )) {
                ForEach(Provider.allCases, id: \.rawValue) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !prefs.providerChoice.requiresKey {
                Label("No API key needed — Ollama runs locally.", systemImage: "laptopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var apiKeySection: some View {
        SettingsSection(title: "API Key") {
            if !prefs.providerChoice.requiresKey {
                Text("Ollama does not require an API key.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let editing = editingKey, editing == prefs.providerChoice {
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
                            prefs.saveKey(draftKey, for: prefs.providerChoice)
                            editingKey = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftKey.isEmpty)

                        Button("Cancel") { editingKey = nil }
                            .buttonStyle(.borderless)
                    }
                }
            } else if prefs.hasKey(for: prefs.providerChoice) {
                HStack {
                    Label("Key saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                    Spacer()
                    Button("Change") {
                        draftKey = ""
                        showKey = false
                        editingKey = prefs.providerChoice
                    }
                    .buttonStyle(.borderless)

                    Button("Remove") {
                        prefs.clearKey(for: prefs.providerChoice)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            } else {
                HStack {
                    Label("No key set", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Spacer()
                    Button("Add Key") {
                        draftKey = ""
                        showKey = false
                        editingKey = prefs.providerChoice
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Text("Stored in ~/.config/blind-spot/keys/\(prefs.providerChoice.rawValue)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var modelSection: some View {
        SettingsSection(title: "Model") {
            HStack {
                TextField(prefs.providerChoice.defaultModel, text: $draftModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Button("Reset") {
                    draftModel = prefs.providerChoice.defaultModel
                    prefs.setModel("", for: prefs.providerChoice)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .onChange(of: draftModel) { _, new in
                prefs.setModel(new, for: prefs.providerChoice)
            }
            .onChange(of: prefs.providerChoice) { _, new in
                draftModel = prefs.currentModel(for: new)
                if new == .ollama {
                    Task { @MainActor in
                        await prefs.refreshOllamaModels()
                        draftModel = prefs.currentModel(for: .ollama)
                    }
                }
            }

            if prefs.providerChoice == .ollama {
                ollamaModelHelper
            } else {
                Text("Default for \(prefs.providerChoice.displayName): \(prefs.providerChoice.defaultModel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var ollamaModelHelper: some View {
        if prefs.ollamaUnreachable {
            HStack {
                Label("Ollama not running at localhost:11434", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
                refreshButton
            }
        } else if prefs.installedOllamaModels.isEmpty {
            HStack {
                Label("No models installed. Try `ollama pull llama3.2`.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                refreshButton
            }
        } else {
            HStack {
                Text("Installed:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Spacer()
                refreshButton
            }
        }
    }

    private var refreshButton: some View {
        Button("Refresh") {
            Task { @MainActor in
                await prefs.refreshOllamaModels()
                draftModel = prefs.currentModel(for: .ollama)
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var accessibilitySection: some View {
        SettingsSection(title: "Accessibility") {
            HStack {
                if axGranted {
                    Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("Not granted", systemImage: "xmark.circle").foregroundStyle(.red)
                }
                Spacer()
                Button("Open System Settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderless)
            }
            .font(.callout)
        }
        .onAppear {
            // Poll for AX status
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                Task { @MainActor in
                    axGranted = AXIsProcessTrusted()
                    if axGranted { t.invalidate() }
                }
            }
        }
    }

    private var hotkeySection: some View {
        SettingsSection(title: "Hotkey") {
            HotkeyRecorder(
                hotkey: prefs.hotkey,
                isRecording: Binding(
                    get: { prefs.isRecordingHotkey },
                    set: { prefs.isRecordingHotkey = $0 }
                ),
                onCapture: { prefs.setHotkey($0) }
            )

            HStack {
                Text("Press the combo over any selected text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if prefs.hotkey != .default {
                    Button("Reset to ⌘⇧Space") { prefs.resetHotkey() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Shared

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
