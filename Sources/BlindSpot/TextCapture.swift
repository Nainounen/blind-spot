import AppKit
import os

private let logger = Logger(subsystem: "com.blindspot.app", category: "TextCapture")

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
    "company.thebrowser.arc",
    "company.thebrowser.Arc",
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

/// Browsers that implement Cocoa's "Use Selection for Find" (⌘E) by writing
/// the selection to the find pasteboard. Arc/Dia remap ⌘E (split view), so
/// they are intentionally excluded.
private let findPasteboardBundleIDs: Set<String> = [
    "com.google.Chrome",
    "com.google.Chrome.beta",
    "com.google.Chrome.dev",
    "com.google.Chrome.canary",
    "com.brave.Browser",
    "com.brave.Browser.beta",
    "com.brave.Browser.nightly",
    "com.microsoft.edgemac",
    "com.microsoft.edgemac.Beta",
    "com.microsoft.edgemac.Dev",
    "com.microsoft.edgemac.Canary",
    "com.operasoftware.Opera",
    "com.operasoftware.OperaNext",
    "com.operasoftware.OperaDeveloper",
    "com.vivaldi.Vivaldi",
    "com.vivaldi.Vivaldi.snapshot",
    "org.chromium.Chromium",
]

struct TextCaptureResult {
    let text: String
    let selectionBounds: CGRect?
}

enum TextCapture {
    /// PIDs whose Chromium AX tree we have already opted into this process.
    private static var axEnabledPIDs = Set<pid_t>()

    /// Like `getSelectedText` but also attempts to capture the on-screen rect of
    /// the selection via the Accessibility API. `selectionBounds` will be nil for
    /// Chromium-based apps (AX parameterized bounds are unreliable there) and for
    /// any app that doesn't expose the attribute.
    static func getSelectedTextWithBounds(from app: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
                                          completion: @escaping (TextCaptureResult?) -> Void) {
        guard let frontApp = app else { completion(nil); return }
        let pid = frontApp.processIdentifier
        let isChromium = isChromiumApp(frontApp)

        // Capture bounds synchronously before any async work — the focused element
        // may change once Cmd+E / Cmd+C is sent.
        let bounds: CGRect? = isChromium ? nil : nativeBounds(pid: pid)

        getSelectedText(from: frontApp) { text in
            guard let t = text, !t.isEmpty else { completion(nil); return }
            completion(TextCaptureResult(text: t, selectionBounds: bounds))
        }
    }

    /// Public entry point used by `ScreenshotCapture` to get AX selection bounds
    /// without going through the full text-capture flow.
    static func exposedBoundsForCurrentSelection(pid: pid_t) -> CGRect? {
        nativeBounds(pid: pid)
    }

    private static func nativeBounds(pid: pid_t) -> CGRect? {
        let axApp = AXUIElementCreateApplication(pid)
        guard let focused = focusedElement(of: axApp) else { return nil }
        return boundsForSelectedText(of: focused)
    }

    private static func boundsForSelectedText(of element: AXUIElement) -> CGRect? {
        var rangeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeVal = rangeRef else { return nil }

        var boundsRef: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeVal as CFTypeRef, &boundsRef
        ) == .success, let bv = boundsRef else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    static func getSelectedText(from app: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
                                completion: @escaping (String?) -> Void) {
        guard let frontApp = app else {
            logger.info("no frontmostApplication")
            completion(nil); return
        }

        let pid      = frontApp.processIdentifier
        let bundleID = frontApp.bundleIdentifier ?? "<unknown>"
        let name     = frontApp.localizedName ?? bundleID
        let chromium = isChromiumApp(frontApp)
        logger.info("frontApp=\(name, privacy: .public) pid=\(pid) bundle=\(bundleID, privacy: .public) chromium=\(chromium)")

        let newlyEnabled = chromium ? enableChromiumAX(pid: pid) : false

        var steps: [(@escaping (String?) -> Void) -> Void] = [
            { done in
                let text = axText(pid: pid, isChromium: chromium)
                if let text, !text.isEmpty {
                    logger.info("AX success: \(text.prefix(60), privacy: .public)")
                } else {
                    logger.info("AX empty")
                }
                done(text)
            }
        ]

        // Chromium builds the AX tree asynchronously after AXManualAccessibility.
        // Only wait on the first opt-in for this PID.
        if chromium && newlyEnabled {
            steps.append { done in
                logger.info("waiting 280ms for Chromium AX tree to settle")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    let text = axText(pid: pid, isChromium: true)
                    if let text, !text.isEmpty {
                        logger.info("AX settle success: \(text.prefix(60), privacy: .public)")
                    }
                    done(text)
                }
            }
        }

        // Chrome/Brave/Edge: ⌘E writes the selection to the find pasteboard
        // without firing JavaScript copy handlers. Do NOT send ⌘E to Arc — it
        // toggles split view.
        if usesFindPasteboard(bundleID) {
            steps.append { done in
                viaFindPasteboard(pid: pid) { text in
                    if let text, !text.isEmpty {
                        logger.info("findPasteboard success: \(text.prefix(60), privacy: .public)")
                    } else {
                        logger.info("findPasteboard empty")
                    }
                    done(text)
                }
            }
            steps.append { done in
                done(axText(pid: pid, isChromium: true))
            }
        }

        // Last resorts. Arc ignores session-tap ⌘C from some sources, so we
        // post to the target PID and then press Edit > Copy via AX.
        steps.append { done in
            logger.info("falling back to clipboard")
            viaClipboard(pid: pid) { text in
                if let text, !text.isEmpty {
                    logger.info("clipboard success: \(text.prefix(60), privacy: .public)")
                } else {
                    logger.info("clipboard empty")
                }
                done(text)
            }
        }
        steps.append { done in
            logger.info("falling back to Edit > Copy")
            viaCopyMenuItem(pid: pid) { text in
                if let text, !text.isEmpty {
                    logger.info("copy menu success: \(text.prefix(60), privacy: .public)")
                } else {
                    logger.info("copy menu empty")
                }
                done(text)
            }
        }

        firstNonEmpty(steps, completion: completion)
    }

    // MARK: - Classification

    private static func isChromiumBundle(_ id: String) -> Bool {
        if chromiumBundleIDs.contains(id) { return true }
        return chromiumBundleIDs.contains { id.hasPrefix($0 + ".") }
    }

    private static func isChromiumApp(_ app: NSRunningApplication) -> Bool {
        if let id = app.bundleIdentifier, isChromiumBundle(id) { return true }
        let name = (app.localizedName ?? "").lowercased()
        return name == "arc" || name.hasPrefix("arc ") || name == "dia"
    }

    private static func usesFindPasteboard(_ bundleID: String) -> Bool {
        if findPasteboardBundleIDs.contains(bundleID) { return true }
        return findPasteboardBundleIDs.contains { bundleID.hasPrefix($0 + ".") }
    }

    private static func axText(pid: pid_t, isChromium: Bool) -> String? {
        if isChromium {
            if let t = chromiumText(pid: pid), !t.isEmpty { return t }
            if let t = nativeText(pid: pid), !t.isEmpty { return t }
            return nil
        }
        return nativeText(pid: pid)
    }

    private static func firstNonEmpty(_ steps: [(@escaping (String?) -> Void) -> Void],
                                      completion: @escaping (String?) -> Void) {
        func run(_ index: Int) {
            guard index < steps.count else { completion(nil); return }
            let step = steps[index]
            step { text in
                if let text, !text.isEmpty { completion(text); return }
                run(index + 1)
            }
        }
        run(0)
    }

    // MARK: - Chromium AX opt-in

    /// Chromium (and Electron) keep the web-content AX tree off until a client
    /// sets `AXManualAccessibility` (or the legacy `AXEnhancedUserInterface`).
    /// Returns true when this PID was opted in for the first time this process,
    /// so the caller can wait for the tree to materialize.
    @discardableResult
    private static func enableChromiumAX(pid: pid_t) -> Bool {
        if axEnabledPIDs.contains(pid) { return false }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 1.0)
        let manual = AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if manual != .success {
            let enhanced = AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            guard enhanced == .success else { return false }
        }
        axEnabledPIDs.insert(pid)
        logger.info("enabled Chromium AX for pid=\(pid)")
        return true
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

        // 4. Dia/Arc don't always proxy the renderer AX tree through the browser
        //    process. Query descendant helper processes directly.
        if let t = rendererProcessText(browserPID: pid), !t.isEmpty { return t }

        return nil
    }

    // MARK: - Renderer subprocess AX

    // Chromium spawns one renderer process per site/tab. On macOS each has its own
    // AX registration. Arc's browser-process AX bridge is often incomplete, so we
    // walk descendant helpers (not just direct children) and query each tree.
    private static func rendererProcessText(browserPID: pid_t) -> String? {
        for rendererPID in descendantPIDs(of: browserPID) {
            enableChromiumAX(pid: rendererPID)
            let axRenderer = AXUIElementCreateApplication(rendererPID)

            if let t = textMarkerText(from: axRenderer), !t.isEmpty { return t }

            if let focused = focusedElement(of: axRenderer) {
                if let t = textMarkerText(from: focused), !t.isEmpty { return t }
                if let t = attributeString(focused, kAXSelectedTextAttribute), !t.isEmpty { return t }
                if let t = walkUpTextMarker(from: focused), !t.isEmpty { return t }
                if let t = walkUpClassic(from: focused), !t.isEmpty { return t }
            }

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

    private static func descendantPIDs(of parentPID: pid_t) -> [pid_t] {
        var byParent: [pid_t: [pid_t]] = [:]
        var size = 0
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        for p in procs {
            byParent[p.kp_eproc.e_ppid, default: []].append(p.kp_proc.p_pid)
        }
        var result: [pid_t] = []
        var stack = byParent[parentPID] ?? []
        while let pid = stack.popLast() {
            result.append(pid)
            stack.append(contentsOf: byParent[pid] ?? [])
        }
        return result
    }

    // Walk Chrome's window tree looking for the AXWebArea role.
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
        guard depth < 30 else { return nil }

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

    // MARK: - Synthetic key posting

    /// Post ⌘+key directly to the target process. A private event source is
    /// used so physically-held modifiers from the hotkey (⇧ from ⌘⇧Space) are
    /// not merged into the synthetic event. Session-wide HID posts are skipped
    /// for the same reason — Arc also ignores some of them.
    private static func postCommandKey(_ virtualKey: CGKeyCode, to pid: pid_t) {
        let src = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.postToPid(pid)
        up?.postToPid(pid)
    }

    // MARK: - Find pasteboard (Chromium fallback, bypasses JS oncopy)

    // Cmd+E = macOS "Use Selection for Find" (NSUseSelectionForFindAction).
    // Chrome handles this at the Cocoa NSResponder level — it reads the selection
    // directly from Blink and writes it to NSPasteboard.Name.find WITHOUT firing
    // any JavaScript copy events. Zone 3-style oncopy handlers are completely blind
    // to this operation. Arc remaps ⌘E and is excluded via `usesFindPasteboard`.
    private static func viaFindPasteboard(pid: pid_t, completion: @escaping (String?) -> Void) {
        let findPboard  = NSPasteboard(name: .find)
        let prevCount   = findPboard.changeCount

        postCommandKey(14, to: pid) // E

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard findPboard.changeCount != prevCount,
                  let text = findPboard.string(forType: .string), !text.isEmpty
            else { completion(nil); return }
            completion(text)
        }
    }

    // MARK: - Clipboard fallback

    private static func viaClipboard(pid: pid_t, completion: @escaping (String?) -> Void) {
        let pb      = NSPasteboard.general
        let prev    = pb.string(forType: .string)
        let prevCnt = pb.changeCount

        // Brief pause so the user can release ⌘⇧ from the hotkey before we
        // inject ⌘C into the target app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            postCommandKey(8, to: pid) // C

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
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
    }

    // MARK: - Copy menu item (for apps that block synthetic ⌘C)

    // Invokes Edit > Copy via the AX menu API instead of injecting a keyboard
    // event. Arc drops some synthetic CGEvents, but AXPress on the Copy item is
    // honoured. Clipboard is snapshotted and restored, same as viaClipboard.
    private static func viaCopyMenuItem(pid: pid_t, completion: @escaping (String?) -> Void) {
        let pb      = NSPasteboard.general
        let prev    = pb.string(forType: .string)
        let prevCnt = pb.changeCount

        let axApp = AXUIElementCreateApplication(pid)
        var menuBarRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef as! AXUIElement? else {
            completion(nil); return
        }

        guard let copyItem = findCopyMenuItem(in: menuBar) else {
            completion(nil); return
        }

        AXUIElementPerformAction(copyItem, kAXPressAction as CFString)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            guard pb.changeCount != prevCnt,
                  let text = pb.string(forType: .string), !text.isEmpty else {
                completion(nil); return
            }
            let captured = text
            pb.clearContents()
            if let p = prev { pb.setString(p, forType: .string) }
            completion(captured)
        }
    }

    /// Finds the Copy item by ⌘C shortcut (locale-independent) or English title.
    private static func findCopyMenuItem(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 6 else { return nil }

        if attributeString(element, kAXMenuItemCmdCharAttribute) == "C" {
            var modsRef: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXMenuItemCmdModifiersAttribute as CFString, &modsRef) == .success,
               let mods = modsRef as? NSNumber {
                // 0 = Command only (Copy). Shift/Option/Control bits mean something else.
                if mods.intValue == 0 { return element }
            } else {
                return element
            }
        }

        if attributeString(element, kAXTitleAttribute) == "Copy" {
            var roleRef: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
            if (roleRef as? String) == "AXMenuItem" { return element }
        }

        guard let children = attributeArray(element, kAXChildrenAttribute) else { return nil }
        for child in children {
            if let found = findCopyMenuItem(in: child as! AXUIElement, depth: depth + 1) {
                return found
            }
        }
        return nil
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
