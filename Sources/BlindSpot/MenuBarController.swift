import AppKit

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem!
    private let onSettings: () -> Void
    private let onShowHistory: (HistoryEntry) -> Void

    init(onSettings: @escaping () -> Void, onShowHistory: @escaping (HistoryEntry) -> Void) {
        self.onSettings = onSettings
        self.onShowHistory = onShowHistory

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "BlindSpot")
            btn.image?.isTemplate = true
        }
        rebuildMenu()

        NotificationCenter.default.addObserver(
            forName: .providerDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in self?.rebuildMenu() }
        }

        NotificationCenter.default.addObserver(
            forName: .historyDidUpdate,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in self?.rebuildMenu() }
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

        // Recent submenu
        let entries = HistoryStore.shared.entries.prefix(5)
        if !entries.isEmpty {
            let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            let recentMenu = NSMenu()
            for entry in entries {
                let label = String(entry.query.prefix(40)) + (entry.query.count > 40 ? "…" : "")
                let item = NSMenuItem(
                    title: label,
                    action: #selector(selectHistory(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = entry.id.uuidString
                item.toolTip = entry.query
                item.target = self
                recentMenu.addItem(item)
            }
            recentItem.submenu = recentMenu
            menu.addItem(recentItem)
        }

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

    @objc private func selectHistory(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr),
              let entry = HistoryStore.shared.entries.first(where: { $0.id == id })
        else { return }
        onShowHistory(entry)
    }

    @objc private func openSettings() {
        onSettings()
    }
}

private extension Provider {
    var menuLabel: String {
        switch self {
        case .openai:    return "OpenAI  (gpt-4o)"
        case .anthropic: return "Anthropic  (claude-sonnet-4-5)"
        case .gemini:    return "Gemini  (gemini-2.5-flash)"
        case .deepseek:  return "DeepSeek  (deepseek-chat)"
        case .grok:      return "Grok  (grok-3)"
        case .ollama:    return "Ollama  (local)"
        }
    }
}

extension Notification.Name {
    static let providerDidChange = Notification.Name("BlindSpotProviderDidChange")
}
