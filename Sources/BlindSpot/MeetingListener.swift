import AVFoundation
import AppKit
import Foundation
import Speech

/// Live meeting listener: transcribes mic (Me) and system audio (Them) separately,
/// and when the other speaker finishes a real request, auto-solves it in the
/// command panel without stealing focus from the call.
@MainActor
final class MeetingListener: ObservableObject {
    static let shared = MeetingListener()

    @Published private(set) var isListening = false
    @Published private(set) var lastError: String?

    private var capture: MeetingAudioCapture?
    private var meTranscriber: LiveTranscriber?
    private var themTranscriber: LiveTranscriber?
    private var reservedLocale: Locale?
    private var ownedReservation = false

    private var utterances: [Utterance] = []
    private var pendingThem = ""
    private var coalesceTask: Task<Void, Never>?
    private var sessionConversationId: UUID?
    private var startTask: Task<Void, Never>?

    private struct Utterance {
        enum Speaker { case me, them }
        let speaker: Speaker
        let text: String
    }

    private init() {}

    func toggle() {
        if isListening {
            Task { await stop() }
        } else {
            start()
        }
    }

    func start() {
        guard !isListening, startTask == nil else { return }
        lastError = nil
        startTask = Task { [weak self] in
            defer { self?.startTask = nil }
            do {
                try await self?.runStart()
            } catch is CancellationError {
                await self?.stop()
            } catch {
                await self?.stop()
                self?.lastError = error.localizedDescription
                print("[BlindSpot] Meeting listener failed: \(error.localizedDescription)")
                NSSound.beep()
            }
        }
    }

    func stop() async {
        startTask?.cancel()
        startTask = nil
        coalesceTask?.cancel()
        coalesceTask = nil
        pendingThem = ""

        capture?.onBuffer = nil
        await capture?.stop()
        capture = nil

        await meTranscriber?.stop()
        await themTranscriber?.stop()
        meTranscriber = nil
        themTranscriber = nil

        if ownedReservation, let locale = reservedLocale {
            await AssetInventory.release(reservedLocale: locale)
        }
        reservedLocale = nil
        ownedReservation = false

        utterances = []
        sessionConversationId = nil

        let wasListening = isListening
        isListening = false
        if wasListening {
            NotificationCenter.default.post(name: .meetingListenerDidChange, object: nil)
        }
    }

    // MARK: - Start internals

    private func runStart() async throws {
        try await requestPermissions()

        let locale = try await LiveTranscriber.prepare(locale: Locale.current)
        ownedReservation = try await AssetInventory.reserve(locale: locale)
        reservedLocale = locale

        let me = LiveTranscriber(speaker: .me)
        let them = LiveTranscriber(speaker: .them)
        me.onFinalPhrase = { [weak self] _, text in
            Task { @MainActor in self?.handleFinal(speaker: .me, text: text) }
        }
        them.onFinalPhrase = { [weak self] _, text in
            Task { @MainActor in self?.handleFinal(speaker: .them, text: text) }
        }
        try await me.start(locale: locale)
        meTranscriber = me
        try await them.start(locale: locale)
        themTranscriber = them

        let capture = MeetingAudioCapture()
        capture.onBuffer = { [weak me, weak them] channel, buffer in
            switch channel {
            case .microphone: me?.yield(buffer)
            case .systemAudio: them?.yield(buffer)
            }
        }
        try await capture.start()
        self.capture = capture

        utterances = []
        sessionConversationId = nil
        isListening = true
        NotificationCenter.default.post(name: .meetingListenerDidChange, object: nil)
    }

    private func requestPermissions() async throws {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speech == .authorized else { throw Failure.speechDenied }

        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else { throw Failure.microphoneDenied }
    }

    // MARK: - Transcript → auto-solve

    private func handleFinal(speaker: Utterance.Speaker, text: String) {
        guard isListening else { return }
        utterances.append(Utterance(speaker: speaker, text: text))
        guard speaker == .them else { return }

        if pendingThem.isEmpty {
            pendingThem = text
        } else {
            pendingThem += " " + text
        }
        coalesceTask?.cancel()
        coalesceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            self?.flushPendingThem()
        }
    }

    private func flushPendingThem() {
        let utterance = pendingThem.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingThem = ""
        coalesceTask = nil
        guard !utterance.isEmpty, isListening else { return }
        guard !shouldSkip(utterance) else { return }
        guard !CommandPanelController.shared.vm.isLoading else { return }
        autoSolve(utterance)
    }

    private func autoSolve(_ utterance: String) {
        let prompt = buildPrompt(utterance: utterance)
        CommandPanelController.shared.show(
            query: prompt,
            conversation: sessionConversation(),
            stealFocus: false
        )
        sessionConversationId = CommandPanelController.shared.vm.activeConversation?.id
    }

    /// Prefer the store (survives panel hide after a completed turn), then the
    /// in-memory panel conversation (first turn may not have been upserted yet).
    private func sessionConversation() -> Conversation? {
        guard let id = sessionConversationId else { return nil }
        if let stored = ConversationStore.shared.conversation(id: id) {
            return stored
        }
        let current = CommandPanelController.shared.vm.activeConversation
        return current?.id == id ? current : nil
    }

    private func buildPrompt(utterance: String) -> String {
        var recent = utterances
        while recent.last?.speaker == .them { recent.removeLast() }
        recent = Array(recent.suffix(8))

        var lines: [String] = [
            "[Live meeting — other speaker]",
            "Them: \(utterance)",
        ]
        if !recent.isEmpty {
            lines.append("")
            lines.append("Recent:")
            for u in recent {
                let who = u.speaker == .me ? "Me" : "Them"
                lines.append("\(who): \(u.text)")
            }
        }
        lines.append("")
        lines.append("Answer their request concisely so I can reply in the meeting.")
        return lines.joined(separator: "\n")
    }

    private func shouldSkip(_ text: String) -> Bool {
        let words = text.split { $0.isWhitespace || $0.isPunctuation }.filter { !$0.isEmpty }
        if words.count < 8 { return true }

        let normalized = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        return Self.fillers.contains(normalized)
    }

    private static let fillers: Set<String> = [
        "yeah", "yes", "yep", "yup", "ok", "okay", "mm-hmm", "mmhmm", "mhm",
        "uh-huh", "uh huh", "thanks", "thank you", "right", "sure", "hmm",
        "uh", "um", "got it", "cool", "alright", "all right", "huh", "nah",
        "nope", "wow", "true", "exactly", "agreed",
    ]

    enum Failure: LocalizedError {
        case speechDenied
        case microphoneDenied

        var errorDescription: String? {
            switch self {
            case .speechDenied:
                return "Speech Recognition permission is required to transcribe the meeting."
            case .microphoneDenied:
                return "Microphone permission is required to separate your voice from others."
            }
        }
    }
}

extension Notification.Name {
    static let meetingListenerDidChange = Notification.Name("BlindSpotMeetingListenerDidChange")
}
