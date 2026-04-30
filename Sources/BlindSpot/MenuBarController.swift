import AppKit

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem!
    private let onSettings: () -> Void

    init(onSettings: @escaping () -> Void) {
        self.onSettings = onSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "BlindSpot")
            btn.image?.isTemplate = true
        }
        rebuildMenu()

        // Rebuild menu when provider changes so the checkmark stays accurate
        NotificationCenter.default.addObserver(
            forName: .providerDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildMenu() }
        }
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let title = NSMenuItem(title: "BlindSpot", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        // Provider submenu
        let provItem = NSMenuItem(
            title: "Provider: \(PreferencesStore.shared.providerChoice.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        let provMenu = NSMenu()
        for p in Provider.allCases {
            let item = NSMenuItem(
                title: p.menuLabel,
                action: #selector(selectProvider(_:)),
                keyEquivalent: ""
            )
            item.representedObject = p.rawValue
            item.target = self
            item.state = p == PreferencesStore.shared.providerChoice ? .on : .off
            provMenu.addItem(item)
        }
        provItem.submenu = provMenu
        menu.addItem(provItem)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit BlindSpot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let p = Provider(rawValue: raw) else { return }
        PreferencesStore.shared.setProvider(p)
        NotificationCenter.default.post(name: .providerDidChange, object: nil)
    }

    @objc private func openSettings() {
        onSettings()
    }
}

private extension Provider {
    var menuLabel: String {
        switch self {
        case .openai:    return "OpenAI  (gpt-4o)"
        case .anthropic: return "Anthropic  (claude-opus-4-5)"
        case .ollama:    return "Ollama  (local)"
        }
    }
}

extension Notification.Name {
    static let providerDidChange = Notification.Name("BlindSpotProviderDidChange")
}
