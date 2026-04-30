import SwiftUI
import AppKit

// MARK: - Window helper

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
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "BlindSpot Setup"
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: view)
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
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

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var step: Step = .welcome
    @State private var selectedProvider: Provider = PreferencesStore.shared.providerChoice
    @State private var apiKey: String = ""
    @State private var showKey: Bool = false
    @State private var axGranted: Bool = AXIsProcessTrusted()
    @State private var axTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            stepView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom nav
            if step != .welcome && step != .done {
                Divider()
                HStack {
                    Button("Back") { go(to: step.previous) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Spacer()
                    nextButton
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }
        }
        .background(.ultraThickMaterial)
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
        withAnimation(.easeInOut(duration: 0.18)) { step = next }
    }

    private var nextButton: some View {
        Button(step.nextLabel) {
            switch step {
            case .welcome: break
            case .provider:
                PreferencesStore.shared.setProvider(selectedProvider)
                go(to: selectedProvider == .ollama ? .accessibility : .apiKey)
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
        .buttonStyle(.borderedProminent)
        .disabled(step == .accessibility && !axGranted)
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
        PreferencesStore.shared.completeOnboarding()
        onComplete()
    }
}

// MARK: - Step: Welcome

private struct WelcomeStep: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkle")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.purple.gradient)
                .padding(.top, 40)

            VStack(spacing: 8) {
                Text("BlindSpot")
                    .font(.system(size: 36, weight: .bold))
                Text("AI answers for anything you select —\ncompletely invisible to screen recorders.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                FeatureBullet(icon: "hand.tap", text: "Select any text, press ⌘⇧Space")
                FeatureBullet(icon: "brain", text: "Get an instant AI answer")
                FeatureBullet(icon: "eye.slash", text: "The overlay is invisible to screen capture")
            }
            .padding(.horizontal, 48)

            Button("Get Started  →") { onStart() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
                .padding(.bottom, 32)
        }
    }
}

private struct FeatureBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.purple)
            Text(text).font(.callout)
        }
    }
}

// MARK: - Step: Provider

private struct ProviderStep: View {
    @Binding var selected: Provider

    var body: some View {
        VStack(spacing: 20) {
            StepHeader(title: "Choose your AI", subtitle: "You can change this anytime from the menu bar.")

            HStack(spacing: 14) {
                ForEach(Provider.allCases, id: \.rawValue) { p in
                    ProviderCard(provider: p, isSelected: selected == p)
                        .onTapGesture { withAnimation { selected = p } }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }
}

private struct ProviderCard: View {
    let provider: Provider
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: provider.icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(isSelected ? .white : .primary)

            Text(provider.displayName)
                .font(.headline)
                .foregroundStyle(isSelected ? .white : .primary)

            Text(provider.cardDescription)
                .font(.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.purple : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.purple : Color.primary.opacity(0.12), lineWidth: 1.5)
        )
    }
}

// MARK: - Step: API Key

private struct APIKeyStep: View {
    let provider: Provider
    @Binding var key: String
    @Binding var showKey: Bool
    @State private var saved = false

    var body: some View {
        VStack(spacing: 20) {
            StepHeader(
                title: "Add your \(provider.displayName) API key",
                subtitle: "Stored locally on your Mac. Never sent anywhere except \(provider.displayName)."
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Group {
                        if showKey {
                            TextField("Paste your API key…", text: $key)
                        } else {
                            SecureField("Paste your API key…", text: $key)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button(showKey ? "Hide" : "Show") { showKey.toggle() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: "lock.fill").font(.caption2)
                    Text("Saved to ~/.config/blind-spot/keys/\(provider.rawValue)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                Link("Get a key at \(provider.keyURL) →", destination: URL(string: "https://\(provider.keyURL)")!)
                    .font(.caption)
            }
            .padding(.horizontal, 32)

            Spacer()

            Text("You can also skip this and add the key later in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
                subtitle: "Required to read selected text and listen for the hotkey."
            )

            VStack(alignment: .leading, spacing: 12) {
                BulletRow(icon: "text.cursor",  text: "Read your selected text without touching the clipboard")
                BulletRow(icon: "keyboard",     text: "Listen for the global hotkey ⌘⇧Space")
                BulletRow(icon: "lock.shield",  text: "BlindSpot only reads text you explicitly select")
            }
            .padding(.horizontal, 40)

            if granted {
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                VStack(spacing: 12) {
                    Button("Open System Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                        onOpen()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Label("Waiting for permission…", systemImage: "clock")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            Spacer()
        }
    }
}

private struct BulletRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(.purple)
            Text(text).font(.callout)
        }
    }
}

// MARK: - Step: Done

private struct DoneStep: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("BlindSpot is ready!")
                    .font(.system(size: 28, weight: .bold))

                Text("Select any text, then press:")
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(["⌘", "⇧", "Space"], id: \.self) { k in
                        KeyBadge(label: k)
                    }
                }
                .font(.title2)

                Text("The  icon in your menu bar gives you settings and provider switching.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                    .padding(.top, 4)
            }

            Button("Start Using BlindSpot") { onComplete() }
                .buttonStyle(.borderedProminent)
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
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Shared UI

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title2.bold())
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
        .padding(.horizontal, 32)
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
    var icon: String {
        switch self {
        case .openai:    return "sparkle"
        case .anthropic: return "brain.head.profile"
        case .ollama:    return "laptopcomputer"
        }
    }

    var cardDescription: String {
        switch self {
        case .openai:    return "GPT-4o\nBest all-round\nNeeds API key"
        case .anthropic: return "Claude\nGreat for reasoning\nNeeds API key"
        case .ollama:    return "Local models\nFree & private\nNo API key"
        }
    }

    var keyURL: String {
        switch self {
        case .openai:    return "platform.openai.com/api-keys"
        case .anthropic: return "console.anthropic.com/settings/keys"
        case .ollama:    return "ollama.com"
        }
    }
}
