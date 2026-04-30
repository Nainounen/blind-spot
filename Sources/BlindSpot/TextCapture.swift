import AppKit

private let chromiumBundleIDs: Set<String> = [
    // Google Chrome
    "com.google.Chrome",
    "com.google.Chrome.beta",
    "com.google.Chrome.dev",
    "com.google.Chrome.canary",
    // Brave
    "com.brave.Browser",
    "com.brave.Browser.beta",
    "com.brave.Browser.nightly",
    // Arc / Dia (The Browser Company)
    "company.thebrowser.Browser",
    "company.thebrowser.dia",
    // Microsoft Edge
    "com.microsoft.edgemac",
    "com.microsoft.edgemac.Beta",
    "com.microsoft.edgemac.Dev",
    "com.microsoft.edgemac.Canary",
    // Opera
    "com.operasoftware.Opera",
    "com.operasoftware.OperaNext",
    "com.operasoftware.OperaDeveloper",
    // Vivaldi
    "com.vivaldi.Vivaldi",
    "com.vivaldi.Vivaldi.snapshot",
    // Ungoogled Chromium / generic Chromium builds
    "org.chromium.Chromium",
    // Sidekick
    "com.pushplaylabs.sidekick",
    // Wavebox
    "com.bookry.wavebox",
    // Sigmaos
    "com.sigmaos.sigmaos",
]

enum TextCapture {
    static func getSelectedText(completion: @escaping (String?) -> Void) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { completion(nil); return }

        let pid        = frontApp.processIdentifier
        let isChromium = chromiumBundleIDs.contains(frontApp.bundleIdentifier ?? "")

        let text = isChromium
            ? chromiumText(pid: pid)
            : nativeText(pid: pid)

        if let t = text, !t.isEmpty {
            completion(t); return
        }

        if isChromium {
            // AX failed. Try Cmd+E ("Use Selection for Find") — a standard macOS
            // NSResponder action that writes selected text to the find pasteboard.
            // Crucially, this fires NO JavaScript events (not a copy action), so
            // oncopy handlers like Zone 3 cannot intercept or poison it.
            viaFindPasteboard { text in
                if let t = text, !t.isEmpty {
                    completion(t); return
                }
                // AX retry at 220 ms (Chrome's async bridge may now be ready).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    let t = chromiumText(pid: pid)
                    completion(t?.isEmpty == false ? t : nil)
                }
            }
        } else {
            viaClipboard(completion: completion)
        }
    }

    // MARK: - Chromium path

    private static func chromiumText(pid: pid_t) -> String? {
        let axApp = AXUIElementCreateApplication(pid)

        // 1. Walk browser-process window tree for AXWebArea (works in Chrome/Brave/Arc).
        if let t = webAreaTextMarker(axApp: axApp), !t.isEmpty { return t }

        // 2. Focused element chain — editable fields in the URL bar / forms.
        if let focused = focusedElement(of: axApp) {
            if let t = walkUpTextMarker(from: focused), !t.isEmpty { return t }
            if let t = walkUpClassic(from: focused), !t.isEmpty { return t }
        }

        // 3. System-wide focused element.
        let sysWide = AXUIElementCreateSystemWide()
        if let el = focusedElement(of: sysWide) {
            if let t = textMarkerText(from: el), !t.isEmpty { return t }
            if let t = attributeString(el, kAXSelectedTextAttribute), !t.isEmpty { return t }
        }

        // 4. Dia (and some other Chromium forks) don't proxy the renderer AX tree
        //    through the browser process. Query each renderer subprocess directly.
        if let t = rendererProcessText(browserPID: pid), !t.isEmpty { return t }

        return nil
    }

    // MARK: - Renderer subprocess AX

    // Chromium spawns one renderer process per site/tab. On macOS each has its own
    // AX registration. Dia's browser-process AX bridge is absent, so we enumerate
    // child processes and query each one's AX tree directly.
    private static func rendererProcessText(browserPID: pid_t) -> String? {
        for rendererPID in childPIDs(of: browserPID) {
            let axRenderer = AXUIElementCreateApplication(rendererPID)

            // Try text-marker (static page text)
            if let t = textMarkerText(from: axRenderer), !t.isEmpty { return t }

            // Try focused element in this renderer
            if let focused = focusedElement(of: axRenderer) {
                if let t = textMarkerText(from: focused), !t.isEmpty { return t }
                if let t = attributeString(focused, kAXSelectedTextAttribute), !t.isEmpty { return t }
                if let t = walkUpTextMarker(from: focused), !t.isEmpty { return t }
                if let t = walkUpClassic(from: focused), !t.isEmpty { return t }
            }

            // BFS renderer's window tree for AXWebArea
            var winsRef: AnyObject?
            if AXUIElementCopyAttributeValue(axRenderer, kAXWindowsAttribute as CFString, &winsRef) == .success,
               let wins = winsRef as? [AXUIElement] {
                for win in wins {
                    if let t = findWebArea(in: win, depth: 0), !t.isEmpty { return t }
                }
            }
        }
        return nil
    }

    private static func childPIDs(of parentPID: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var size = 0
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        for p in procs where p.kp_eproc.e_ppid == parentPID {
            result.append(p.kp_proc.p_pid)
        }
        return result
    }

    // Walk Chrome's window tree (max 7 levels) looking for the AXWebArea role.
    // AXSelectedTextMarkerRange on the web area covers all static text selections.
    private static func webAreaTextMarker(axApp: AXUIElement) -> String? {
        // Try focused window first, then all windows (Dia doesn't always set focusedWindow).
        var candidates: [AXUIElement] = []

        var winRef: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
           let win = winRef { candidates.append(win as! AXUIElement) }

        var mainRef: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &mainRef) == .success,
           let win = mainRef { candidates.append(win as! AXUIElement) }

        var winsRef: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &winsRef) == .success,
           let wins = winsRef as? [AXUIElement] { candidates.append(contentsOf: wins) }

        for win in candidates {
            if let t = findWebArea(in: win, depth: 0), !t.isEmpty { return t }
        }
        return nil
    }

    private static func findWebArea(in element: AXUIElement, depth: Int) -> String? {
        guard depth < 20 else { return nil }

        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        if role == "AXWebArea" {
            if let t = textMarkerText(from: element), !t.isEmpty { return t }
            if let t = attributeString(element, kAXSelectedTextAttribute), !t.isEmpty { return t }
            // Still descend — selected text may live on a child node
        }

        guard let children = attributeArray(element, kAXChildrenAttribute) else { return nil }
        for child in children {
            if let t = findWebArea(in: child as! AXUIElement, depth: depth + 1) { return t }
        }
        return nil
    }

    // MARK: - Native app path

    private static func nativeText(pid: pid_t) -> String? {
        let axApp = AXUIElementCreateApplication(pid)
        if let focused = focusedElement(of: axApp) {
            if let t = attributeString(focused, kAXSelectedTextAttribute), !t.isEmpty { return t }
            if let t = walkUpClassic(from: focused), !t.isEmpty { return t }
        }
        return bfsWindows(in: axApp)
    }

    // MARK: - Text-marker helpers

    private static func textMarkerText(from el: AXUIElement) -> String? {
        var range: AnyObject?
        guard AXUIElementCopyAttributeValue(
            el, "AXSelectedTextMarkerRange" as CFString, &range
        ) == .success, let r = range else { return nil }

        var text: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            el, "AXStringForTextMarkerRange" as CFString, r, &text
        ) == .success else { return nil }

        return text as? String
    }

    private static func walkUpTextMarker(from element: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 15 else { return nil }
        if let t = textMarkerText(from: element), !t.isEmpty { return t }
        var parent: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
              let p = parent else { return nil }
        return walkUpTextMarker(from: p as! AXUIElement, depth: depth + 1)
    }

    // MARK: - Classic AX helpers

    private static func focusedElement(of el: AXUIElement) -> AXUIElement? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXFocusedUIElementAttribute as CFString, &v) == .success else { return nil }
        return (v as! AXUIElement)
    }

    private static func walkUpClassic(from element: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 15 else { return nil }
        if let t = attributeString(element, kAXSelectedTextAttribute), !t.isEmpty { return t }
        var parent: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
              let p = parent else { return nil }
        return walkUpClassic(from: p as! AXUIElement, depth: depth + 1)
    }

    private static func bfsWindows(in axApp: AXUIElement) -> String? {
        guard let windows = attributeArray(axApp, kAXWindowsAttribute) else { return nil }
        for window in windows {
            if let t = bfs(root: window as! AXUIElement, maxDepth: 10) { return t }
        }
        return nil
    }

    private static func bfs(root: AXUIElement, maxDepth: Int) -> String? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (el, depth) = queue.removeFirst()
            if let t = attributeString(el, kAXSelectedTextAttribute), !t.isEmpty { return t }
            guard depth < maxDepth,
                  let children = attributeArray(el, kAXChildrenAttribute) else { continue }
            queue.append(contentsOf: children.map { ($0 as! AXUIElement, depth + 1) })
        }
        return nil
    }

    // MARK: - Find pasteboard (Chromium fallback, bypasses JS oncopy)

    // Cmd+E = macOS "Use Selection for Find" (NSUseSelectionForFindAction).
    // Chrome handles this at the Cocoa NSResponder level — it reads the selection
    // directly from Blink and writes it to NSPasteboard.Name.find WITHOUT firing
    // any JavaScript copy events. Zone 3-style oncopy handlers are completely blind
    // to this operation.
    private static func viaFindPasteboard(completion: @escaping (String?) -> Void) {
        let findPboard  = NSPasteboard(name: .find)
        let prevCount   = findPboard.changeCount

        // Virtual key 14 = 'E' on US/ISO keyboards
        let src  = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 14, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 14, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard findPboard.changeCount != prevCount,
                  let text = findPboard.string(forType: .string), !text.isEmpty
            else { completion(nil); return }
            completion(text)
        }
    }

    // MARK: - Clipboard fallback (non-Chromium only)

    private static func viaClipboard(completion: @escaping (String?) -> Void) {
        let pb      = NSPasteboard.general
        let prev    = pb.string(forType: .string)
        let prevCnt = pb.changeCount

        let src  = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let text: String?
            if pb.changeCount != prevCnt {
                text = pb.string(forType: .string)
                pb.clearContents()
                if let p = prev { pb.setString(p, forType: .string) }
            } else {
                text = nil
            }
            completion(text)
        }
    }

    // MARK: - Low-level helpers

    private static func attributeString(_ el: AXUIElement, _ attr: String) -> String? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func attributeArray(_ el: AXUIElement, _ attr: String) -> [AnyObject]? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? [AnyObject]
    }
}
