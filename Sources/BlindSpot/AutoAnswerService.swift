import AppKit

// MARK: - Models

private struct ChoiceOption {
    let label: String
    let element: AXUIElement
}

private enum TargetKind {
    case textField(AXUIElement)
    case choiceGroup(options: [ChoiceOption], isMultiSelect: Bool)
    case selectField(AXUIElement, options: [ChoiceOption])
    case orderingList(container: AXUIElement, hiddenInput: AXUIElement, items: [ChoiceOption])
}

private struct AnswerTarget {
    let frame: CGRect
    let kind: TargetKind
}

private struct ChoiceElement {
    let element: AXUIElement
    let frame: CGRect
}

// MARK: - Service

/// Answers exam questions via AX. Supports:
/// - Text input (short answer, essay, numerical)
/// - Radio / checkbox (multichoice single/multi, true/false)
/// - Select dropdown (match, gapselect)
/// - Ordering (drag-to-reorder lists)
@MainActor
final class AutoAnswerService {
    static let shared = AutoAnswerService()
    private var currentTask: Task<Void, Never>?

    private init() {}

    // ──────────────────────────────────────────────
    //  Public API
    // ──────────────────────────────────────────────

    func run() {
        currentTask?.cancel()
        guard AXIsProcessTrusted() else { return }

        let sysWide = AXUIElementCreateSystemWide()
        guard let focused = axFocusedElement(sysWide) else { return }
        let role = axRole(focused)

        if let target = singleTarget(for: focused, role: role) {
            processTarget(target)
        }
    }

    func runAnswerAll() {
        currentTask?.cancel()
        guard AXIsProcessTrusted() else { return }

        let sysWide = AXUIElementCreateSystemWide()
        var appRef: AnyObject?
        guard AXUIElementCopyAttributeValue(sysWide, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
              let app = appRef as! AXUIElement? else { return }
        var winRef: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let win = winRef as! AXUIElement? else { return }

        let allTargets = collectAnswerTargets(in: win)
        print("[AutoAnswer] Found \(allTargets.count) answer targets")

        currentTask = Task {
            for (i, target) in allTargets.enumerated() {
                guard !Task.isCancelled else { return }
                let question = extractQuestion(for: target, allTargets: allTargets, index: i)
                print("[AutoAnswer] Q\(i+1): \"\(question.prefix(80))...\"")
                guard !question.isEmpty else { continue }

                switch target.kind {
                case .textField(let el):
                    do {
                        let answer = try await askAI(question: question, options: nil)
                        print("[AutoAnswer] Q\(i+1) answer: \"\(answer.prefix(60))\"")
                        pasteAnswer(answer, into: el)
                    } catch { print("[AutoAnswer] q\(i+1) text error: \(error.localizedDescription)") }

                case .choiceGroup(let options, let isMulti):
                    let labels = options.map { $0.label }
                    print("[AutoAnswer] Q\(i+1) choice options(\(labels.count)): \(labels.joined(separator: " | "))")
                    guard labels.count >= 2 else { continue }
                    do {
                        let answer = try await askAI(question: question, options: labels, isMultiSelect: isMulti)
                        print("[AutoAnswer] Q\(i+1) choice answer: \"\(answer)\"")
                        selectChoice(options: options, isMultiSelect: isMulti, answer: answer)
                    } catch { print("[AutoAnswer] q\(i+1) choice error: \(error.localizedDescription)") }

                case .selectField(let el, let options):
                    let labels = options.map { $0.label }
                    print("[AutoAnswer] Q\(i+1) select options(\(labels.count)): \(labels.joined(separator: " | "))")
                    guard labels.count >= 2 else { continue }
                    do {
                        let answer = try await askAI(question: question, options: labels)
                        print("[AutoAnswer] Q\(i+1) select answer: \"\(answer)\"")
                        selectDropdown(el, options: options, answer: answer)
                    } catch { print("[AutoAnswer] q\(i+1) select error: \(error.localizedDescription)") }

                case .orderingList(_, let hiddenInput, let items):
                    let itemLabels = items.map { $0.label }
                    print("[AutoAnswer] Q\(i+1) ordering items(\(itemLabels.count)): \(itemLabels.joined(separator: " | "))")
                    do {
                        let answer = try await askAIForOrdering(question: question, items: itemLabels)
                        print("[AutoAnswer] Q\(i+1) ordering answer: \"\(answer)\"")
                        applyOrdering(answer: answer, hiddenInput: hiddenInput, items: items)
                    } catch { print("[AutoAnswer] q\(i+1) ordering error: \(error.localizedDescription)") }
                }

                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    // ──────────────────────────────────────────────
    //  Single‑target dispatch
    // ──────────────────────────────────────────────

    private func singleTarget(for focused: AXUIElement, role: String) -> AnswerTarget? {
        if role == "AXTextField" || role == "AXTextArea" {
            guard let frame = axFrame(focused) else { return nil }
            return AnswerTarget(frame: frame, kind: .textField(focused))
        }

        if role == "AXPopUpButton" || role == "AXComboBox" {
            guard let frame = axFrame(focused) else { return nil }
            let options = menuOptions(for: focused)
            return AnswerTarget(frame: frame, kind: .selectField(focused, options: options))
        }

        if role == "AXRadioButton" || role == "AXCheckBox" {
            guard let win = ancestorWindow(of: focused) else { return nil }
            let allChoices = collectAllChoiceElements(in: win)
            let groups = clusterByProximity(allChoices)
            for group in groups {
                if group.contains(where: { CFEqual($0.element, focused) }),
                   let firstFrame = group.first?.frame {
                    let labels = group.compactMap { choiceLabel(for: $0.element) }
                    guard labels.count >= 2 else { continue }
                    let elements = group.map { $0.element }
                    let isMulti = group.contains { axRole($0.element) == "AXCheckBox" }
                    let options = zip(labels, elements).map { ChoiceOption(label: $0.0, element: $0.1) }
                    let yMin = group.map { $0.frame.origin.y }.min()!
                    let yMax = group.map { $0.frame.maxY }.max()!
                    return AnswerTarget(frame: CGRect(x: firstFrame.origin.x, y: yMin,
                        width: firstFrame.width, height: yMax - yMin),
                        kind: .choiceGroup(options: options, isMultiSelect: isMulti))
                }
            }
        }

        return nil
    }

    private func processTarget(_ target: AnswerTarget) {
        let question = extractQuestion(for: target, allTargets: [target], index: 0)
        guard !question.isEmpty else { return }

        currentTask = Task {
            switch target.kind {
            case .textField(let el):
                do {
                    let answer = try await askAI(question: question, options: nil)
                    pasteAnswer(answer, into: el)
                } catch { print("[AutoAnswer] \(error.localizedDescription)") }

            case .choiceGroup(let options, let isMulti):
                let labels = options.map { $0.label }
                guard labels.count >= 2 else { return }
                do {
                    let answer = try await askAI(question: question, options: labels, isMultiSelect: isMulti)
                    selectChoice(options: options, isMultiSelect: isMulti, answer: answer)
                } catch { print("[AutoAnswer] \(error.localizedDescription)") }

            case .selectField(let el, let options):
                let labels = options.map { $0.label }
                guard labels.count >= 2 else { return }
                do {
                    let answer = try await askAI(question: question, options: labels)
                    selectDropdown(el, options: options, answer: answer)
                } catch { print("[AutoAnswer] \(error.localizedDescription)") }

            case .orderingList(_, let hiddenInput, let items):
                let itemLabels = items.map { $0.label }
                do {
                    let answer = try await askAIForOrdering(question: question, items: itemLabels)
                    applyOrdering(answer: answer, hiddenInput: hiddenInput, items: items)
                } catch { print("[AutoAnswer] \(error.localizedDescription)") }
            }
        }
    }

    // ──────────────────────────────────────────────
    //  Question extraction
    // ──────────────────────────────────────────────

    private func extractQuestion(for target: AnswerTarget, allTargets: [AnswerTarget], index: Int) -> String {
        let fieldTop = target.frame.origin.y
        let lowerBound: CGFloat = index > 0 ? allTargets[index - 1].frame.maxY : fieldTop - 400

        let root = ancestorWindow(of: targetElement(target)) ?? targetElement(target)
        var hits: [(bottom: CGFloat, text: String)] = []
        walkForText(from: root, lowerBound: lowerBound, upperBound: fieldTop, hits: &hits, depth: 0)

        guard !hits.isEmpty else {
            return extractByTree(around: targetElement(target))
        }
        return String(hits.sorted { $0.bottom < $1.bottom }.map { $0.text }.joined(separator: " ").prefix(1500))
    }

    private func targetElement(_ target: AnswerTarget) -> AXUIElement {
        switch target.kind {
        case .textField(let el):                 return el
        case .choiceGroup(let options, _):       return options.first?.element ?? (options.first?.element)!
        case .selectField(let el, _):            return el
        case .orderingList(let container, _, _): return container
        }
    }

    private func walkForText(from element: AXUIElement, lowerBound: CGFloat, upperBound: CGFloat,
                             hits: inout [(bottom: CGFloat, text: String)], depth: Int) {
        guard depth < 25 else { return }
        let role = axRole(element)
        let skip: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox",
                                  "AXRadioButton", "AXCheckBox", "AXPopUpButton"]
        if skip.contains(role) { return }

        if role == "AXStaticText" || role == "AXHeading" {
            if let text = axString(element, kAXValueAttribute),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let frame = axFrame(element) {
                let bottom = frame.maxY
                if bottom > lowerBound && bottom <= upperBound {
                    hits.append((bottom: bottom, text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            return
        }
        if let frame = axFrame(element), (frame.origin.y >= upperBound || frame.maxY <= lowerBound) { return }
        for child in axChildren(element) {
            walkForText(from: child, lowerBound: lowerBound, upperBound: upperBound, hits: &hits, depth: depth + 1)
        }
    }

    private func extractByTree(around element: AXUIElement) -> String {
        var current = element
        for _ in 0..<8 {
            var parentRef: AnyObject?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = parentRef else { break }
            let text = subtreeText(from: parent as! AXUIElement, excluding: element)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 20 { return String(text.prefix(1500)) }
            current = parent as! AXUIElement
        }
        return ""
    }

    private func subtreeText(from element: AXUIElement, excluding excluded: AXUIElement, depth: Int = 0) -> String {
        guard depth < 20 else { return "" }
        if CFEqual(element, excluded) { return "" }
        let skip: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox",
                                  "AXRadioButton", "AXCheckBox", "AXPopUpButton"]
        if skip.contains(axRole(element)) { return "" }
        var parts: [String] = []
        if axRole(element) == "AXStaticText" || axRole(element) == "AXHeading" {
            let t = axString(element, kAXValueAttribute) ?? axString(element, kAXTitleAttribute) ?? ""
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        for child in axChildren(element) {
            let t = subtreeText(from: child, excluding: excluded, depth: depth + 1)
            if !t.isEmpty { parts.append(t) }
        }
        return parts.joined(separator: " ")
    }

    // ──────────────────────────────────────────────
    //  Target collection (Answer All)
    // ──────────────────────────────────────────────

    private func collectAnswerTargets(in root: AXUIElement) -> [AnswerTarget] {
        var targets: [AnswerTarget] = []

        // 1. Text fields & selects & ordering
        collectInputFields(from: root, into: &targets, depth: 0)

        // 2. Radio/checkbox groups via proximity clustering
        let allChoices = collectAllChoiceElements(in: root)
        let groups = clusterByProximity(allChoices)

        for group in groups {
            guard group.first != nil else { continue }
            let elements = group.map { $0.element }
            let labels = group.compactMap { choiceLabel(for: $0.element) }
            guard labels.count >= 2 else { continue }
            let isMulti = group.contains { axRole($0.element) == "AXCheckBox" }
            let options = zip(labels, elements).map { ChoiceOption(label: $0.0, element: $0.1) }
            let yMin = group.map { $0.frame.origin.y }.min()!
            let yMax = group.map { $0.frame.maxY }.max()!
            let xMin = group.map { $0.frame.origin.x }.min()!
            let xMax = group.map { $0.frame.maxX }.max()!
            targets.append(AnswerTarget(frame: CGRect(x: xMin, y: yMin, width: xMax - xMin, height: yMax - yMin),
                                        kind: .choiceGroup(options: options, isMultiSelect: isMulti)))
        }

        return targets.sorted { $0.frame.origin.y < $1.frame.origin.y }
    }

    private func collectInputFields(from element: AXUIElement, into targets: inout [AnswerTarget], depth: Int) {
        guard depth < 25 else { return }
        let role = axRole(element)

        if role == "AXTextField" || role == "AXTextArea" {
            if let frame = axFrame(element) {
                targets.append(AnswerTarget(frame: frame, kind: .textField(element)))
            }
            return
        }

        if role == "AXPopUpButton" || role == "AXComboBox" {
            if let frame = axFrame(element) {
                let options = menuOptions(for: element)
                if options.count >= 2 {
                    targets.append(AnswerTarget(frame: frame, kind: .selectField(element, options: options)))
                }
            }
            return
        }

        // Detect Moodle ordering question: a <ul> with sortable items and a hidden input
        if role == "AXGroup" {
            let children = axChildren(element)
            // Look for a hidden input nearby (stores the order)
            let hiddenInputs = children.filter { axRole($0) == "AXTextField" && axFrame($0) == nil }
            // Also check if this group contains list items with move buttons
            let hasSortableItems = children.contains { child in
                let childRole = axRole(child)
                return childRole == "AXList" || childRole == "AXGroup"
            }
            if !hiddenInputs.isEmpty && hasSortableItems {
                // Collect sortable item labels
                var orderingItems: [ChoiceOption] = []
                collectOrderingItems(from: element, into: &orderingItems)
                if orderingItems.count >= 2, let hiddenInput = hiddenInputs.first,
                   let frame = axFrame(element) {
                    targets.append(AnswerTarget(frame: frame, kind: .orderingList(
                        container: element, hiddenInput: hiddenInput, items: orderingItems)))
                    return
                }
            }
        }

        if role == "AXRadioButton" || role == "AXCheckBox" { return }
        for child in axChildren(element) {
            collectInputFields(from: child, into: &targets, depth: depth + 1)
        }
    }

    /// Recursively collects item labels from a Moodle ordering sortable list.
    private func collectOrderingItems(from element: AXUIElement, into items: inout [ChoiceOption]) {
        for child in axChildren(element) {
            let role = axRole(child)
            if role == "AXStaticText" {
                if let text = axString(child, kAXValueAttribute),
                   !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    items.append(ChoiceOption(label: text, element: child))
                }
            }
            // Moodle items have data-itemcontent attribute — the text is inside nested groups
            if role == "AXGroup" || role == "AXList" {
                collectOrderingItems(from: child, into: &items)
            }
        }
    }

    private func collectAllChoiceElements(in root: AXUIElement) -> [ChoiceElement] {
        var result: [ChoiceElement] = []
        walkForChoices(from: root, into: &result)
        return result
    }

    private func walkForChoices(from element: AXUIElement, into result: inout [ChoiceElement]) {
        let role = axRole(element)
        if role == "AXRadioButton" || role == "AXCheckBox" {
            if let frame = axFrame(element), frame.width > 0, frame.height > 0 {
                result.append(ChoiceElement(element: element, frame: frame))
            }
            return
        }
        if role == "AXTextField" || role == "AXTextArea" || role == "AXPopUpButton" { return }
        for child in axChildren(element) {
            walkForChoices(from: child, into: &result)
        }
    }

    private func clusterByProximity(_ items: [ChoiceElement]) -> [[ChoiceElement]] {
        guard items.count >= 2 else { return [] }
        let sorted = items.sorted { $0.frame.origin.y < $1.frame.origin.y }
        var groups: [[ChoiceElement]] = []
        var current: [ChoiceElement] = [sorted[0]]

        for i in 1..<sorted.count {
            let gap = sorted[i].frame.origin.y - current.last!.frame.maxY
            if gap < 50 { current.append(sorted[i]) }
            else { groups.append(current); current = [sorted[i]] }
        }
        groups.append(current)
        return groups.filter { $0.count >= 2 }
    }

    // ──────────────────────────────────────────────
    //  Label extraction
    // ──────────────────────────────────────────────

    private func choiceLabel(for element: AXUIElement) -> String? {
        // 1. kAXTitleAttribute — Safari resolves aria-labelledby / <label for=…> here
        if let t = axString(element, kAXTitleAttribute), !t.trimmingCharacters(in: .whitespaces).isEmpty { return t }
        // 2. kAXDescriptionAttribute
        if let t = axString(element, kAXDescriptionAttribute), !t.trimmingCharacters(in: .whitespaces).isEmpty { return t }
        // 3. Parent AXGroup's AXStaticText children (<label><input>Text</label>)
        var parentRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
              let parent = parentRef else { return nil }
        let parentEl = parent as! AXUIElement
        for sibling in axChildren(parentEl) {
            if axRole(sibling) == "AXStaticText",
               let t = axString(sibling, kAXValueAttribute),
               !t.trimmingCharacters(in: .whitespaces).isEmpty { return t }
        }
        // 4. Grandparent's static text (deeper nesting in Moodle .r0/.r1 wrappers)
        var gpRef: AnyObject?
        if AXUIElementCopyAttributeValue(parentEl, kAXParentAttribute as CFString, &gpRef) == .success,
           let gp = gpRef {
            for sibling in axChildren(gp as! AXUIElement) {
                if axRole(sibling) == "AXStaticText",
                   let t = axString(sibling, kAXValueAttribute),
                   !t.trimmingCharacters(in: .whitespaces).isEmpty { return t }
            }
        }
        return nil
    }

    private func menuOptions(for selectEl: AXUIElement) -> [ChoiceOption] {
        var result: [ChoiceOption] = []
        for child in axChildren(selectEl) {
            let role = axRole(child)
            if role == "AXMenuItem" || role == "AXMenuButtonItem" || role == "AXStaticText" {
                let text = axString(child, kAXTitleAttribute)
                    ?? axString(child, kAXValueAttribute)
                    ?? axString(child, kAXDescriptionAttribute)
                    ?? ""
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(ChoiceOption(label: trimmed, element: child)) }
            }
        }
        return result
    }

    // ──────────────────────────────────────────────
    //  Choice / select / ordering actions
    // ──────────────────────────────────────────────

    private func selectChoice(options: [ChoiceOption], isMultiSelect: Bool, answer: String) {
        let cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if isMultiSelect {
            // Extract single-letter tokens: handles "A, C", "A C", "A and C", "A,C,E", etc.
            let tokens = cleaned.components(separatedBy: CharacterSet(charactersIn: ",;&/ \n\t"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count == 1 && $0.first?.isLetter == true }
            let selectedLetters = Set(tokens)
            print("[AutoAnswer] multi-select parsed letters: \(selectedLetters)")
            for (i, opt) in options.enumerated() {
                if selectedLetters.contains(choiceLetter(i)) {
                    pressElement(opt.element)
                }
            }
            // If no letters parsed, try fuzzy text match for each option
            if selectedLetters.isEmpty {
                for opt in options {
                    if !opt.label.isEmpty, cleaned.localizedCaseInsensitiveContains(opt.label.uppercased()) {
                        pressElement(opt.element)
                    }
                }
            }
        } else {
            for (i, opt) in options.enumerated() {
                let letter = choiceLetter(i)
                if cleaned.hasPrefix(letter) || cleaned.contains("(\(letter))") || cleaned.contains("\(letter))") {
                    pressElement(opt.element); return
                }
            }
            for opt in options {
                if !opt.label.isEmpty, cleaned.localizedCaseInsensitiveContains(opt.label.uppercased()) {
                    pressElement(opt.element); return
                }
            }
        }
    }

    private func selectDropdown(_ selectEl: AXUIElement, options: [ChoiceOption], answer: String) {
        let cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        var targetOption: ChoiceOption?
        for (i, opt) in options.enumerated() {
            let letter = choiceLetter(i)
            if cleaned.hasPrefix(letter) || cleaned.contains("(\(letter))") || cleaned.contains("\(letter))") {
                targetOption = opt; break
            }
        }
        if targetOption == nil {
            for opt in options {
                if !opt.label.isEmpty, cleaned.localizedCaseInsensitiveContains(opt.label.uppercased()) {
                    targetOption = opt; break
                }
            }
        }
        guard let target = targetOption else { return }

        // Try AX value set first
        if AXUIElementSetAttributeValue(selectEl, kAXValueAttribute as CFString, target.label as CFString) == .success {
            return
        }
        // Try pressing the menu item
        if AXUIElementPerformAction(target.element, kAXPressAction as CFString) == .success { return }
        // Keyboard fallback
        focusElement(selectEl)
        AXUIElementPerformAction(selectEl, kAXShowMenuAction as CFString)
        Thread.sleep(forTimeInterval: 0.1)
        if let firstChar = target.label.first {
            let keyCode = keyCodeFor(char: firstChar)
            postKey(keyCode)
            Thread.sleep(forTimeInterval: 0.05)
        }
        postKey(36) // Return
    }

    /// Applies the AI-returned ordering to a Moodle ordering question via its hidden input.
    private func applyOrdering(answer: String, hiddenInput: AXUIElement, items: [ChoiceOption]) {
        // The AI returns a comma-separated list of letters like "C, A, D, B"
        // We need to set the hidden input's value and trigger an input event
        let cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let letters = cleaned.components(separatedBy: CharacterSet(charactersIn: ",;&/ \n\t"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count == 1 && $0.first?.isLetter == true }

        guard !letters.isEmpty else { return }

        // Map letters to ChoiceOptions in order
        var orderedItems: [ChoiceOption] = []
        for letter in letters {
            if let idx = letterIndex(letter) {
                let i = min(idx, items.count - 1)
                orderedItems.append(items[i])
            }
        }
        guard !orderedItems.isEmpty else { return }

        // For Moodle: we'd need to map item IDs to their MD5 hash keys.
        // Since we can't easily get those from AX, we write the ordered labels
        // as a string. The JS drag_reorder module expects MD5 hashes though.
        // This is a best-effort: write the ordered item text to trigger JS.
        let orderedValue = orderedItems.map { $0.label }.joined(separator: ",")
        print("[AutoAnswer] ordering value: \(orderedValue)")
        AXUIElementSetAttributeValue(hiddenInput, kAXValueAttribute as CFString, orderedValue as CFString)
    }

    private func askAIForOrdering(question: String, items: [String]) async throws -> String {
        let labeled = items.enumerated().map { "\(choiceLetter($0))) \($1)" }.joined(separator: "\n")
        let systemPrompt = "Put these items in the correct logical order. Respond with ONLY the letters in the correct sequence, separated by commas (e.g. \"C, A, D, B\"). No explanation."
        let profile = ProfilesStore.shared.activeProfile
        let messages: [ConversationMessage] = [
            ConversationMessage(role: .system, content: systemPrompt),
            ConversationMessage(role: .user, content: "Arrange: \(question)\n\nItems:\n\(labeled)")
        ]
        let stream = try await AIService.query(messages, profile: profile)
        var response = ""
        for try await chunk in stream {
            guard !Task.isCancelled else { throw CancellationError() }
            response += chunk
        }
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func choiceLetter(_ index: Int) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let idx = letters.index(letters.startIndex, offsetBy: min(index, 25))
        return String(letters[idx])
    }

    private func letterIndex(_ letter: String) -> Int? {
        guard letter.count == 1, let first = letter.uppercased().first else { return nil }
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        return letters.firstIndex(of: first).map { letters.distance(from: letters.startIndex, to: $0) }
    }

    private func pressElement(_ el: AXUIElement) {
        if AXUIElementPerformAction(el, kAXPressAction as CFString) == .success { return }
        AXUIElementPerformAction(el, kAXConfirmAction as CFString)
    }

    // ──────────────────────────────────────────────
    //  AI
    // ──────────────────────────────────────────────

    private func askAI(question: String, options: [String]?, isMultiSelect: Bool = false) async throws -> String {
        let systemPrompt: String
        let userMessage: String

        if let opts = options, !opts.isEmpty {
            let labeled = opts.enumerated().map { "\(choiceLetter($0))) \($1)" }.joined(separator: "\n")
            if isMultiSelect {
                systemPrompt = "Answer this exam question. There are MULTIPLE correct answers — you MUST select ALL that apply. Respond with the correct letters separated by commas (e.g. \"A, C, E\"). ONLY the letters, no explanation, no additional text whatsoever."
            } else {
                systemPrompt = "Answer this exam question. Respond with ONLY the single letter of the correct option (e.g. \"B\"). No explanation, no additional text."
            }
            userMessage = "Question: \(question)\n\nOptions:\n\(labeled)"
        } else {
            systemPrompt = "Answer this exam question directly and concisely. Respond with only the answer — one word, number, or short phrase. No preamble, no explanation."
            userMessage = question
        }

        let profile = ProfilesStore.shared.activeProfile
        let messages: [ConversationMessage] = [
            ConversationMessage(role: .system, content: systemPrompt),
            ConversationMessage(role: .user, content: userMessage)
        ]

        let stream = try await AIService.query(messages, profile: profile)
        var response = ""
        for try await chunk in stream {
            guard !Task.isCancelled else { throw CancellationError() }
            response += chunk
        }
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ──────────────────────────────────────────────
    //  Paste (clipboard-first for WebKit compatibility)
    // ──────────────────────────────────────────────

    private func pasteAnswer(_ answer: String, into element: AXUIElement) {
        // Focus the target field first — essential for WebKit
        focusElement(element)

        // Use clipboard paste (works universally in Safari/WebKit)
        let pb = NSPasteboard.general
        let prev = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(answer, forType: .string)

        let src = CGEventSource(stateID: .hidSystemState)
        func post(_ key: CGKeyCode, flags: CGEventFlags) {
            let dn = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
            dn?.flags = flags; up?.flags = flags
            dn?.post(tap: .cgAnnotatedSessionEventTap)
            up?.post(tap: .cgAnnotatedSessionEventTap)
        }

        // Select all existing content (if any), then paste
        post(0, flags: .maskCommand)  // Cmd+A
        post(9, flags: .maskCommand)  // Cmd+V

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            pb.clearContents()
            if let p = prev { pb.setString(p, forType: .string) }
        }
    }

    /// Move focus to the target element. Tries multiple strategies.
    private func focusElement(_ el: AXUIElement) {
        // 1. AX focus attribute
        if AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success {
            Thread.sleep(forTimeInterval: 0.08)
            return
        }

        // 2. Click at element center
        if let frame = axFrame(el) {
            let cx = frame.origin.x + frame.width / 2
            let cy = frame.origin.y + frame.height / 2
            let src = CGEventSource(stateID: .hidSystemState)
            let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                               mouseCursorPosition: CGPoint(x: cx, y: cy), mouseButton: .left)
            let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                             mouseCursorPosition: CGPoint(x: cx, y: cy), mouseButton: .left)
            down?.post(tap: .cgAnnotatedSessionEventTap)
            up?.post(tap: .cgAnnotatedSessionEventTap)
            Thread.sleep(forTimeInterval: 0.12)
        }
    }

    // ──────────────────────────────────────────────
    //  Keyboard helpers
    // ──────────────────────────────────────────────

    private func postKey(_ keyCode: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func keyCodeFor(char: Character) -> CGKeyCode {
        switch char.lowercased().first {
        case "a": return 0;  case "s": return 1;  case "d": return 2;  case "f": return 3
        case "h": return 4;  case "g": return 5;  case "z": return 6;  case "x": return 7
        case "c": return 8;  case "v": return 9;  case "b": return 11; case "q": return 12
        case "w": return 13; case "e": return 14; case "r": return 15; case "y": return 16
        case "t": return 17; case "1": return 18; case "2": return 19; case "3": return 20
        case "4": return 21; case "6": return 22; case "5": return 23; case "=": return 24
        case "9": return 25; case "7": return 26; case "-": return 27; case "8": return 28
        case "0": return 29; case "]": return 30; case "o": return 31; case "u": return 32
        case "[": return 33; case "i": return 34; case "p": return 35; case "l": return 37
        case "j": return 38; case "'": return 39; case "k": return 40; case ";": return 41
        case "\\": return 42; case ",": return 43; case "/": return 44; case "n": return 45
        case "m": return 46; case ".": return 47; case " ": return 49
        default: return 0
        }
    }

    // ──────────────────────────────────────────────
    //  AX helpers
    // ──────────────────────────────────────────────

    private func ancestorWindow(of element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<20 {
            if axRole(current) == "AXWindow" { return current }
            var parentRef: AnyObject?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = parentRef else { return nil }
            current = parent as! AXUIElement
        }
        return nil
    }

    private func axFocusedElement(_ el: AXUIElement) -> AXUIElement? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref else { return nil }
        return (ref as! AXUIElement)
    }

    private func axRole(_ el: AXUIElement) -> String {
        var ref: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &ref)
        return ref as? String ?? ""
    }

    private func axChildren(_ el: AXUIElement) -> [AXUIElement] {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success,
              let arr = ref as? [AXUIElement] else { return [] }
        return arr
    }

    private func axString(_ el: AXUIElement, _ attr: String) -> String? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private func axFrame(_ el: AXUIElement) -> CGRect? {
        var posRef: AnyObject?; var sizeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let pr = posRef, let sr = sizeRef else { return nil }
        var pos = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(pr as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sr as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: pos, size: size)
    }
}
