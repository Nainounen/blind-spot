import AppKit

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem!
    private let onSettings: () -> Void
    private let onShowConversation: (Conversation) -> Void
    private let onCheckForUpdates: () -> Void

    init(
        onSettings: @escaping () -> Void,
        onShowConversation: @escaping (Conversation) -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.onSettings = onSettings
        self.onShowConversation = onShowConversation
        self.onCheckForUpdates = onCheckForUpdates

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "BlindSpot")
            btn.image?.isTemplate = true
        }
        rebuildMenu()

        NotificationCenter.default.addObserver(
            forName: .conversationsDidUpdate,
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

        // Profiles submenu
        let profiles = ProfilesStore.shared.profiles
        let activeId = ProfilesStore.shared.activeProfileId
        if !profiles.isEmpty {
            let profileItem = NSMenuItem(
                title: "Profile: \(ProfilesStore.shared.activeProfile.name)",
                action: nil,
                keyEquivalent: ""
            )
            let profileMenu = NSMenu()
            for profile in profiles {
                let item = NSMenuItem(
                    title: profile.name,
                    action: #selector(selectProfile(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = profile.id.uuidString
                item.target = self
                item.state = profile.id == activeId ? .on : .off
                profileMenu.addItem(item)
            }
            profileItem.submenu = profileMenu
            menu.addItem(profileItem)
        }

        // Recent conversations submenu
        let convs = ConversationStore.shared.conversations.prefix(5)
        if !convs.isEmpty {
            let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            let recentMenu = NSMenu()
            for conv in convs {
                let label: String = {
                    let t = conv.title.isEmpty ? "Untitled" : conv.title
                    return String(t.prefix(40)) + (t.count > 40 ? "…" : "")
                }()
                let item = NSMenuItem(
                    title: label,
                    action: #selector(selectConversation(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = conv.id.uuidString
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

        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit BlindSpot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr)
        else { return }
        ProfilesStore.shared.activate(id)
        rebuildMenu()
    }

    @objc private func selectConversation(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr),
              let conv = ConversationStore.shared.conversation(id: id)
        else { return }
        onShowConversation(conv)
    }

    @objc private func openSettings() {
        onSettings()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates()
    }
}

extension Notification.Name {
    static let providerDidChange = Notification.Name("BlindSpotProviderDidChange")
}
