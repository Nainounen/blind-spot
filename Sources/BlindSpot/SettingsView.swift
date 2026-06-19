import SwiftUI
import AppKit

// MARK: - Settings tab

private enum SettingsTab: String, CaseIterable {
    case profiles      = "Profiles"
    case apiKeys       = "API Keys"
    case preferences   = "Preferences"
    case hotkeys       = "Hotkeys"
    case accessibility = "Permissions"
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
        // Switch to .regular BEFORE creating the window so SwiftUI controls
        // render with the correct system appearance from the start (fixes grey
        // sliders and invisible text in the release build).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

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
            w.appearance = NSApp.effectiveAppearance
            let hostingView = NSHostingView(rootView: SettingsView())
            let glassView = NSGlassEffectView()
            glassView.contentView = hostingView
            w.contentView = glassView
            w.center()
            w.delegate = self
            window = w
        }
        CommandPanelController.shared.hide()
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

@MainActor
struct SettingsView: View {
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var selectedTab: SettingsTab = .profiles
    @State private var editingKeyFor: Provider? = nil
    @State private var draftKey: String = ""
    @State private var showKey: Bool = false
    @State private var axGranted: Bool = AXIsProcessTrusted()
    @State private var screenRecordingGranted: Bool = CGPreflightScreenCaptureAccess()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.4)
            contentPane
        }
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
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
                        ProviderIcon(provider: provider, size: 18)
                            .foregroundStyle(prefs.hasKey(for: provider) ? Color.primary : Color.secondary.opacity(0.5))

                        Text(provider.displayName)
                            .frame(width: 90, alignment: .leading)
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
                        Divider().padding(.leading, 28)
                    }
                }

                Divider().padding(.leading, 28)
                HStack(spacing: 10) {
                    ProviderIcon(provider: .ollama, size: 18)
                        .foregroundStyle(Color.primary)
                    Text("Ollama")
                        .frame(width: 90, alignment: .leading)
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("Panel Size")
                        .font(.callout)
                    Picker("Panel Size", selection: Binding(
                        get: { prefs.panelSizePreset },
                        set: {
                            prefs.setPanelSizePreset($0)
                            CommandPanelController.shared.resizePanel(animated: true)
                        }
                    )) {
                        ForEach(PanelSizePreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 280)
                    Text("XS hides the sidebar and shows a compact bar. Takes effect immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: Binding(
                    get: { prefs.savePanelPosition },
                    set: { prefs.setSavePanelPosition($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remember panel position")
                            .font(.callout)
                        Text("When on, the panel reopens at its last dragged position instead of centered on screen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

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

                Divider()

                // Screenshot capture size
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Screenshot Padding")
                                .font(.callout)
                            Spacer()
                            Text("\(Int(prefs.screenshotPadding))px")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { prefs.screenshotPadding },
                                set: { prefs.setScreenshotPadding($0) }
                            ),
                            in: 80...800, step: 20
                        )
                        Text("How far beyond the selected text to expand the capture area on each side.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Minimum Capture Size")
                                .font(.callout)
                            Spacer()
                            Text("\(Int(prefs.screenshotMinWidth))×\(Int(prefs.screenshotMinHeight))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Width").font(.caption2).foregroundStyle(.tertiary)
                                Slider(
                                    value: Binding(
                                        get: { prefs.screenshotMinWidth },
                                        set: { prefs.setScreenshotMinSize(width: $0, height: prefs.screenshotMinHeight) }
                                    ),
                                    in: 100...2000, step: 40
                                )
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Height").font(.caption2).foregroundStyle(.tertiary)
                                Slider(
                                    value: Binding(
                                        get: { prefs.screenshotMinHeight },
                                        set: { prefs.setScreenshotMinSize(width: prefs.screenshotMinWidth, height: $0) }
                                    ),
                                    in: 100...2000, step: 40
                                )
                            }
                        }
                        Text("Ensures a minimum screenshot size even when selecting a small region.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Live preview — show what the capture dimensions look like
                    screenshotPreview
                }
            }
        }
    }

    // MARK: - Screenshot Preview

    private var screenshotPreview: some View {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenW = screen?.frame.width ?? 1512
        let screenH = screen?.frame.height ?? 982
        let pad = prefs.screenshotPadding
        let minW = prefs.screenshotMinWidth
        let minH = prefs.screenshotMinHeight

        // Typical text selection: ~300px wide, ~20px tall (one line)
        let selW: CGFloat = 300
        let selH: CGFloat = 20
        let capW = max(selW + 2 * pad, minW)
        let capH = max(selH + 2 * pad, minH)

        // Scale everything to fit a ~260×160 mini-map
        let mapMaxW: CGFloat = 260
        let mapMaxH: CGFloat = 160
        let scale = min(mapMaxW / screenW, mapMaxH / screenH)
        let mapSW = screenW * scale
        let mapSH = screenH * scale
        let mapSelW = max(selW * scale, 3)
        let mapSelH = max(selH * scale, 2)
        let mapCapW = max(capW * scale, 6)
        let mapCapH = max(capH * scale, 4)

        // Figure out Mac model from screen resolution (points)
        let modelName: String = {
            let w = Int(screenW), h = Int(screenH)
            switch (w, h) {
            case (1512, 982):  return "14\" MacBook Pro"
            case (1728, 1117): return "16\" MacBook Pro"
            case (1470, 956):  return "13\" MacBook Air"
            case (1710, 1107): return "15\" MacBook Air"
            default:           return "\(w)×\(h) display"
            }
        }()

        let pctW = Int(capW / screenW * 100)
        let pctH = Int(capH / screenH * 100)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Capture preview on \(modelName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("~\(Int(capW))×\(Int(capH)) px (\(pctW)%×\(pctH)%)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Mini-map: screen rectangle with selection and capture overlay
            ZStack {
                // Screen
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    .frame(width: mapSW, height: mapSH)

                // Capture area (blue, centred — appears larger around the selection)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: mapCapW, height: mapCapH)

                // Selected text (dark outline, centred — sits on top of the capture area)
                RoundedRectangle(cornerRadius: 1)
                    .strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
                    .background(Color.primary.opacity(0.25))
                    .frame(width: mapSelW, height: mapSelH)
            }
            .frame(width: mapSW, height: mapSH)
            .frame(maxWidth: .infinity)

            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.35)).frame(width: 10, height: 5)
                    Text("Selection").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.accentColor.opacity(0.45)).frame(width: 10, height: 5)
                    Text("Capture").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Hotkeys tab

    private var hotkeysSection: some View {
        SettingsSection(title: "Hotkeys") {
            VStack(spacing: 0) {
                hotkeyRow(
                    label: "Trigger",
                    hotkey: prefs.hotkey,
                    isRecording: $prefs.isRecordingHotkey,
                    onCapture: { prefs.setHotkey($0) },
                    defaultHotkey: .default,
                    resetLabel: "⌘⇧Space",
                    resetAction: { prefs.resetHotkey() },
                    description: "Ask about selected text"
                )
                Divider().opacity(0.3).padding(.leading, 84)
                hotkeyRow(
                    label: "Visual Context",
                    hotkey: prefs.visualContextHotkey,
                    isRecording: $prefs.isRecordingVisualContextHotkey,
                    onCapture: { prefs.setVisualContextHotkey($0) },
                    defaultHotkey: .defaultVisualContext,
                    resetLabel: "⌘⇧⌥Space",
                    resetAction: { prefs.resetVisualContextHotkey() },
                    description: "Ask with screenshot"
                )
                Divider().opacity(0.3).padding(.leading, 84)
                hotkeyRow(
                    label: "Auto-Answer",
                    hotkey: prefs.autoAnswerHotkey,
                    isRecording: $prefs.isRecordingAutoAnswerHotkey,
                    onCapture: { prefs.setAutoAnswerHotkey($0) },
                    defaultHotkey: .defaultAutoAnswer,
                    resetLabel: "⌘⌥A",
                    resetAction: { prefs.resetAutoAnswerHotkey() },
                    description: "Answer current question"
                )
                Divider().opacity(0.3).padding(.leading, 84)
                hotkeyRow(
                    label: "Answer All",
                    hotkey: prefs.answerAllHotkey,
                    isRecording: $prefs.isRecordingAnswerAllHotkey,
                    onCapture: { prefs.setAnswerAllHotkey($0) },
                    defaultHotkey: .defaultAnswerAll,
                    resetLabel: "⌘⌥⇧A",
                    resetAction: { prefs.resetAnswerAllHotkey() },
                    description: "Answer every question"
                )
                Divider().opacity(0.3).padding(.leading, 84)
                hotkeyRow(
                    label: "Panic Quit",
                    hotkey: prefs.panicHotkey,
                    isRecording: $prefs.isRecordingPanicHotkey,
                    onCapture: { prefs.setPanicHotkey($0) },
                    defaultHotkey: .defaultPanic,
                    resetLabel: "⌘⌥Q",
                    resetAction: { prefs.resetPanicHotkey() },
                    description: "Force-quit instantly"
                )
            }
        }
    }

    private func hotkeyRow(
        label: String,
        hotkey: Hotkey,
        isRecording: Binding<Bool>,
        onCapture: @escaping (Hotkey) -> Void,
        defaultHotkey: Hotkey,
        resetLabel: String,
        resetAction: @escaping () -> Void,
        description: String
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.callout)
                .frame(width: 80, alignment: .leading)
                .foregroundStyle(.primary)

            HotkeyRecorder(
                hotkey: hotkey,
                isRecording: isRecording,
                onCapture: onCapture
            )

            if hotkey != defaultHotkey {
                Button("Reset to \(resetLabel)") { resetAction() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Accessibility tab

    private var accessibilitySection: some View {
        SettingsSection(title: "Permissions") {
            VStack(alignment: .leading, spacing: 16) {
                // -- Accessibility --
                permissionRow(
                    icon: "text.cursor",
                    title: "Accessibility",
                    description: "Read selected text from any app without touching the clipboard, and listen for global hotkeys.",
                    usedBy: "⌘⇧Space, ⌘⇧⌥Space, ⌘⌥A, ⌘⌥⇧A, ⌘⌥Q",
                    granted: axGranted,
                    openURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )

                Divider()

                // -- Screen Recording --
                permissionRow(
                    icon: "camera.viewfinder",
                    title: "Screen Recording",
                    description: "Capture a screenshot of the area around your selected text so the AI can see visual context like UI, diagrams, or code layout.",
                    usedBy: "⌘⇧⌥Space (Visual Context)",
                    granted: screenRecordingGranted,
                    openURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                )

                if axGranted && screenRecordingGranted {
                    Divider()
                    Label("All permissions granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }
        }
        .onAppear {
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                let axOK = AXIsProcessTrusted()
                let srOK = CGPreflightScreenCaptureAccess()
                if axOK && srOK { t.invalidate() }
                Task { @MainActor in
                    axGranted = axOK
                    screenRecordingGranted = srOK
                }
            }
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        usedBy: String,
        granted: Bool,
        openURL: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.bold())
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(usedBy)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if !granted {
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: openURL)!)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    // MARK: - About tab

    private var versionSection: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return SettingsSection(title: "About") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("BlindSpot \(version)")
                        .font(.callout)
                    Spacer()
                    Link("Release notes ↗", destination: URL(string: "https://github.com/Nainounen/blind-spot/releases/tag/v\(version)")!)
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                        .underline()
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Credits")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Link("unveroleone", destination: URL(string: "https://github.com/unveroleone")!)
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                    Link("nainounen", destination: URL(string: "https://github.com/nainounen")!)
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                }
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

    @State private var isActiveProfile: Bool = false
    @State private var ollamaModels: [OllamaService.Model] = []
    @State private var ollamaLoading: Bool = false

    private func autosave() {
        guard !draft.name.isEmpty, !draft.model.isEmpty else { return }
        onSave(draft)
    }

    private var temperatureDisabled: Bool {
        draft.thinkingEnabled && draft.provider != .anthropic
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Name
                VStack(alignment: .leading, spacing: 5) {
                    fieldLabel("Name")
                    TextField("Profile name", text: $draft.name)
                        .textFieldStyle(.plain)
                        .glassField()
                        .onChange(of: draft.name) { _, _ in autosave() }
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
                                autosave()
                            }
                        )) {
                            ForEach(Provider.allCases, id: \.rawValue) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 120)

                        if draft.provider == .ollama {
                            ollamaModelPicker
                        } else {
                            TextField("Model identifier", text: $draft.model)
                                .textFieldStyle(.plain)
                                .glassField()
                                .onChange(of: draft.model) { _, _ in autosave() }
                        }
                    }
                }
                .task(id: draft.provider) {
                    guard draft.provider == .ollama else { return }
                    ollamaLoading = true
                    ollamaModels = await OllamaService.listInstalledModels() ?? []
                    ollamaLoading = false
                    if !ollamaModels.isEmpty && !ollamaModels.contains(where: { $0.name == draft.model }) {
                        draft.model = ollamaModels[0].name
                        autosave()
                    }
                }

                // Vision overrides (for visual context requests via ⌘⇧⌥Space)
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("Visual Context (⌘⇧⌥Space)")

                    HStack(spacing: 8) {
                        Text("Provider").font(.caption).foregroundStyle(.secondary).frame(width: 55, alignment: .leading)
                        Picker("", selection: Binding(
                            get: { draft.visionProvider ?? draft.provider },
                            set: { p in
                                draft.visionProvider = p == draft.provider ? nil : p
                                autosave()
                            }
                        )) {
                            Text(draft.provider.supportsVision ? "Same as text" : "None (not supported)").tag(draft.provider)
                            ForEach(Provider.allCases.filter { $0.supportsVision }, id: \.rawValue) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    HStack(spacing: 8) {
                        Text("Model").font(.caption).foregroundStyle(.secondary).frame(width: 55, alignment: .leading)
                        TextField("Default for provider", text: Binding(
                            get: { draft.visionModel ?? "" },
                            set: { v in
                                draft.visionModel = v.isEmpty ? nil : v
                                autosave()
                            }
                        ))
                        .textFieldStyle(.plain)
                        .glassField()
                    }

                    Text("Use a different provider or model for screenshot requests. For example, route via Gemini for vision even when your text queries go through DeepSeek.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

                // System Prompt
                VStack(alignment: .leading, spacing: 5) {
                    fieldLabel("System Prompt")
                    TextEditor(text: $draft.systemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 90)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .onChange(of: draft.systemPrompt) { _, _ in autosave() }
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
                                set: { draft.maxOutputTokens = Int($0); autosave() }
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
                                .foregroundStyle(temperatureDisabled ? .tertiary : .secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { draft.temperature },
                                set: { draft.temperature = $0; autosave() }
                            ),
                            in: 0.0...2.0, step: 0.1
                        )
                        .disabled(temperatureDisabled)
                        .opacity(temperatureDisabled ? 0.35 : 1.0)
                        if temperatureDisabled {
                            Text("Temperature is ignored when thinking mode is on for this provider.")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else {
                            Text("Lower = focused · Higher = creative")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

                // Thinking / Reasoning
                if draft.provider.supportsThinking {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $draft.thinkingEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable thinking / reasoning")
                                    .font(.callout)
                                Text(draft.provider.thinkingDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: draft.thinkingEnabled) { _, _ in autosave() }

                        if draft.thinkingEnabled {
                            HStack(spacing: 10) {
                                fieldLabel("Effort")
                                Picker("", selection: $draft.reasoningEffort) {
                                    ForEach(ReasoningEffort.allCases, id: \.self) { e in
                                        Text(e.displayName).tag(e)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: draft.reasoningEffort) { _, _ in autosave() }
                            }
                            Text("Higher effort = more thinking tokens = better on hard tasks, but slower and pricier.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                }

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
                }
                .padding(.top, 4)
            }
            .padding(18)
        }
        .onAppear {
            isActiveProfile = (draft.id == ProfilesStore.shared.activeProfileId)
        }
    }

    @ViewBuilder
    private var ollamaModelPicker: some View {
        if ollamaLoading {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Loading models…").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassField()
        } else if ollamaModels.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Model identifier", text: $draft.model)
                    .textFieldStyle(.plain)
                    .glassField()
                    .onChange(of: draft.model) { _, _ in autosave() }
                Text("Ollama not running or no models installed. Type a model name manually.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            Picker("", selection: Binding(
                get: { draft.model },
                set: { draft.model = $0; autosave() }
            )) {
                ForEach(ollamaModels, id: \.name) { m in
                    Text(m.name).tag(m.name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
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
