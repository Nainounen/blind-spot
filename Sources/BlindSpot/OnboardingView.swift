import SwiftUI
import AppKit

// MARK: - Window helper

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onComplete: (() -> Void)?

    func show() {
        if window == nil {
            let view = OnboardingView { [weak self] in
                self?.window?.close()
                self?.onComplete?()
            }
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 680),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = ""
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            let hostingView = NSHostingView(rootView: view)
            w.contentView = hostingView
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

// MARK: - Main view

private enum Step: Int, CaseIterable {
    case welcome, provider, apiKey, accessibility, done
}

@MainActor
struct OnboardingView: View {
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var selectedProvider: Provider = PreferencesStore.shared.providerChoice
    @State private var apiKey: String = ""
    @State private var showKey: Bool = false
    @State private var axGranted: Bool = AXIsProcessTrusted()
    @State private var axTimer: Timer?

    private var setupSteps: [Step] {
        selectedProvider.requiresKey ? [.provider, .apiKey, .accessibility] : [.provider, .accessibility]
    }

    private var stepNumber: Int { (setupSteps.firstIndex(of: step) ?? 0) + 1 }

    private var stepLabels: [String] {
        setupSteps.map { $0 == .provider ? "Provider" : $0 == .apiKey ? "API key" : "Permissions" }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("BlindSpot", systemImage: "sparkle")
                    .font(.headline)
                Spacer()
                if step != .welcome && step != .done {
                    Text("Step \(stepNumber) of \(setupSteps.count)")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text(step == .done ? "Ready to go" : "Welcome").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 44)
            .padding(.bottom, 20)

            if step != .welcome && step != .done {
                StepDots(current: stepNumber, labels: stepLabels)
                    .padding(.bottom, 24)
            }

            ScrollView {
                stepView
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .id(step)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom nav
            if step != .welcome && step != .done {
                Divider().opacity(0.4)
                HStack {
                    Button("Back") {
                        let previous = step == .accessibility && !selectedProvider.requiresKey ? Step.provider : step.previous
                        go(to: previous)
                    }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    Spacer()
                    nextButton
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { axTimer?.invalidate() }
    }

    // MARK: - Step routing

    @ViewBuilder
    private var stepView: some View {
        switch step {
        case .welcome:      WelcomeStep { go(to: .provider) }
        case .provider:     ProviderStep(selected: $selectedProvider)
        case .apiKey:       APIKeyStep(provider: selectedProvider, key: $apiKey, showKey: $showKey)
        case .accessibility: AccessibilityStep(granted: $axGranted, onOpen: startAXTimer)
        case .done:         DoneStep(onComplete: finish)
        }
    }

    // MARK: - Navigation

    private func go(to next: Step) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { step = next }
    }

    private var nextButton: some View {
        Button(step.nextLabel) {
            switch step {
            case .welcome: break
            case .provider:
                PreferencesStore.shared.setProvider(selectedProvider)
                if selectedProvider == .ollama {
                    Task { @MainActor in await PreferencesStore.shared.refreshOllamaModels() }
                }
                go(to: selectedProvider.requiresKey ? .apiKey : .accessibility)
            case .apiKey:
                if !apiKey.isEmpty {
                    PreferencesStore.shared.saveKey(apiKey, for: selectedProvider)
                }
                go(to: .accessibility)
            case .accessibility:
                go(to: .done)
            case .done:
                finish()
            }
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: [])
    }

    private func startAXTimer() {
        axTimer?.invalidate()
        axTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                axGranted = AXIsProcessTrusted()
                if axGranted { axTimer?.invalidate() }
            }
        }
    }

    private func finish() {
        let store = ProfilesStore.shared
        if let idx = store.profiles.firstIndex(where: { $0.name == "Default" }) {
            var updated = store.profiles[idx]
            updated.provider = selectedProvider
            updated.model = selectedProvider.defaultModel
            store.update(updated)
        } else {
            store.create(AIProfile(
                name: "Default",
                provider: selectedProvider,
                model: selectedProvider.defaultModel
            ))
        }
        PreferencesStore.shared.completeOnboarding()
        onComplete()
    }
}

// MARK: - Step dots

private struct StepDots: View {
    let current: Int
    let labels: [String]

    private var total: Int { labels.count }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(1...total, id: \.self) { index in
                HStack(spacing: 6) {
                    Image(systemName: "\(index).circle.fill")
                        .foregroundStyle(index <= current ? Color.accentColor : Color.secondary)
                    Text(labels[index - 1])
                        .font(.callout.weight(index == current ? .semibold : .regular))
                        .foregroundStyle(index == current ? .primary : .secondary)
                }
                if index < total {
                    Rectangle().fill(.quaternary).frame(width: 24, height: 1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup step \(current) of \(total)")
    }
}

// MARK: - Step: Welcome

private struct WelcomeStep: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkle")
                .font(.system(size: 44, weight: .medium))
                .frame(width: 88, height: 88)
                .background(.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 24))
                .foregroundStyle(.purple.gradient)
                .padding(.top, 16)

            VStack(spacing: 6) {
                Text("BlindSpot")
                    .font(.system(size: 32, weight: .bold))
                Text("Answers for anything you select.\nRight where you work.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                FeatureBullet(icon: "hand.tap",  text: "Select any text, press ⌘⇧Space")
                FeatureBullet(icon: "camera.viewfinder", text: "Or ⌘⇧⌥Space to include a screenshot for visual context")
                FeatureBullet(icon: "brain",     text: "Get an instant AI answer")
                FeatureBullet(icon: "eye.slash", text: "The overlay is invisible to screen capture")
            }
            .padding(16)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 40)

            Button("Get Started") { onStart() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
                .padding(.bottom, 24)
        }
    }
}

private struct FeatureBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.purple)
            Text(text).font(.callout)
        }
    }
}

// MARK: - Step: Provider

private struct ProviderStep: View {
    @Binding var selected: Provider

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 16) {
            StepHeader(title: "Choose your AI", subtitle: "You can change this anytime from the menu bar.")

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Provider.allCases, id: \.rawValue) { p in
                    Button {
                        selected = p
                    } label: {
                        ProviderCard(provider: p, isSelected: selected == p)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(p.displayName)
                    .accessibilityValue(selected == p ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selected == p ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

private struct ProviderCard: View {
    let provider: Provider
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ProviderIcon(provider: provider, size: 26)
                .frame(width: 40, height: 40)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                Text(provider.displayName).font(.body.weight(.semibold))
                Text(provider.cardDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(.title3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(
            isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Step: API Key

private struct APIKeyStep: View {
    let provider: Provider
    @Binding var key: String
    @Binding var showKey: Bool

    var body: some View {
        VStack(spacing: 20) {
            StepHeader(
                title: "Add your \(provider.displayName) API key",
                subtitle: "Stored locally on your Mac. Never sent anywhere except \(provider.displayName)."
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    PasteableKeyField(
                        placeholder: "Paste your API key…",
                        text: $key,
                        isSecure: !showKey
                    )
                    .id(showKey)
                    .frame(height: 22)

                    Button(showKey ? "Hide" : "Show") { showKey.toggle() }
                        .buttonStyle(.borderless)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))

                HStack(spacing: 5) {
                    Image(systemName: "lock.fill").font(.caption2)
                    Text("Stored on this Mac")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                if let url = provider.signupURL {
                    Link("Get a key →", destination: URL(string: url)!)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            Text("You can also skip this and add the key later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
    }
}

// MARK: - Step: Accessibility

private struct AccessibilityStep: View {
    @Binding var granted: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            StepHeader(
                title: "Allow Accessibility Access",
                subtitle: "Required to read selected text and listen for the hotkey. Screen Recording is needed to capture screenshots with visual context."
            )

            VStack(alignment: .leading, spacing: 12) {
                BulletRow(icon: "text.cursor",  text: "Read your selected text without touching the clipboard")
                BulletRow(icon: "keyboard",     text: "Listen for the global hotkeys ⌘⇧Space and ⌘⇧⌥Space")
                BulletRow(icon: "camera.viewfinder", text: "Capture screenshots for visual context (⌘⇧⌥Space)")
                BulletRow(icon: "lock.shield",  text: "BlindSpot only reads text and regions you explicitly target")
            }
            .padding(16)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 28)

            if granted {
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                VStack(spacing: 10) {
                    Button("Open System Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                        onOpen()
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

                    Label("Waiting for permission…", systemImage: "clock")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            Spacer()

            if !granted {
                Text("You can also skip this and grant access later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
        }
    }
}

private struct BulletRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.purple)
            Text(text).font(.callout)
        }
    }
}

// MARK: - Step: Done

private struct DoneStep: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("BlindSpot is ready!")
                    .font(.system(size: 26, weight: .bold))

                VStack(spacing: 8) {
                    Text("Select any text, then press:")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(["⌘", "⇧", "Space"], id: \.self) { k in
                            KeyBadge(label: k)
                        }
                    }

                    Text("Add Option for visual context:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    HStack(spacing: 6) {
                        ForEach(["⌘", "⇧", "⌥", "Space"], id: \.self) { k in
                            KeyBadge(label: k)
                        }
                    }
                }
                .font(.title3)

                Text("Open BlindSpot in the menu bar to switch providers or change settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 4)

                Text("Your default profile is ready. Add more in Settings → Profiles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 4)
            }

            Button("Start Using BlindSpot") { onComplete() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])

            Spacer()
        }
    }
}

private struct KeyBadge: View {
    let label: String
    var body: some View {
        Text(label)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.13), lineWidth: 1))
    }
}

// MARK: - Shared UI

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
        .padding(.horizontal, 28)
    }
}

// MARK: - Step navigation helpers

private extension Step {
    var nextLabel: String {
        switch self {
        case .welcome:       return "Get Started"
        case .provider:      return "Next"
        case .apiKey:        return "Save & Continue"
        case .accessibility: return "Continue"
        case .done:          return "Done"
        }
    }

    var previous: Step {
        Step(rawValue: rawValue - 1) ?? .welcome
    }
}

// MARK: - Provider extensions for UI

private extension Provider {
    var cardDescription: String {
        switch self {
        case .openai:     return "OpenAI models · API key"
        case .anthropic:  return "Claude models · API key"
        case .gemini:     return "Google models · API key"
        case .deepseek:   return "DeepSeek models · API key"
        case .grok:       return "xAI models · API key"
        case .openrouter: return "Many providers · One API key"
        case .ollama:     return "Local models · No key needed"
        case .local:      return "Compatible servers · Local"
        }
    }
}
