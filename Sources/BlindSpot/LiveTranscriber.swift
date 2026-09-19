import AVFoundation
import Foundation
import Speech

/// On-device streaming transcription for one audio channel (Me or Them).
///
/// Uses SpeechAnalyzer / SpeechTranscriber — the macOS 26 model Notes uses
/// for meetings. Audio stays on-device; volatile (partial) results are ignored
/// and only finalized phrases are reported to the listener.
final class LiveTranscriber: @unchecked Sendable {
    enum Speaker: String, Sendable {
        case me
        case them
    }

    let speaker: Speaker
    var onFinalPhrase: (@Sendable (Speaker, String) -> Void)?

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?
    private var converter: AnalyzerBufferConverter?

    init(speaker: Speaker) {
        self.speaker = speaker
    }

    /// Download locale assets if needed. Call once before starting any channels.
    static func prepare(locale: Locale) async throws -> Locale {
        guard SpeechTranscriber.isAvailable else {
            throw Failure.transcriberUnavailable
        }
        let resolved: Locale
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            resolved = match
        } else if let english = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US")) {
            resolved = english
        } else {
            throw Failure.unsupportedLocale(locale.identifier)
        }

        let probe = SpeechTranscriber(
            locale: resolved,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
            try await request.downloadAndInstall()
        }
        return resolved
    }

    func start(locale: Locale) async throws {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw Failure.noCompatibleAudioFormat
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (inputSequence, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: inputSequence)

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.inputContinuation = continuation
        self.converter = AnalyzerBufferConverter(outputFormat: analyzerFormat)

        let speaker = self.speaker
        resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { return }
                    guard result.isFinal else { continue }
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    self?.onFinalPhrase?(speaker, text)
                }
            } catch is CancellationError {
                // Expected during stop.
            } catch {
                print("[BlindSpot] \(speaker.rawValue) transcription failed: \(error.localizedDescription)")
            }
        }
    }

    func yield(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let inputContinuation else { return }
        do {
            let converted = try converter.convert(buffer)
            guard converted.frameLength > 0 else { return }
            inputContinuation.yield(AnalyzerInput(buffer: converted))
        } catch {
            // Skip a bad buffer rather than tearing down the session.
        }
    }

    func stop() async {
        inputContinuation?.finish()
        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                await analyzer.cancelAndFinishNow()
                resultTask?.cancel()
            }
        } else {
            resultTask?.cancel()
        }
        await resultTask?.value
        resultTask = nil
        inputContinuation = nil
        converter = nil
        analyzer = nil
        transcriber = nil
    }

    enum Failure: LocalizedError, Sendable {
        case transcriberUnavailable
        case unsupportedLocale(String)
        case noCompatibleAudioFormat

        var errorDescription: String? {
            switch self {
            case .transcriberUnavailable:
                return "On-device speech transcription is unavailable on this Mac."
            case .unsupportedLocale(let id):
                return "Speech transcription is unavailable for \(id)."
            case .noCompatibleAudioFormat:
                return "No audio format is compatible with the speech transcriber."
            }
        }
    }
}

// MARK: - PCM → SpeechAnalyzer format

/// Converts capture buffers (mic or SCStream) into the format SpeechAnalyzer wants.
/// Recreates the AVAudioConverter if the input format changes (device swap).
private final class AnalyzerBufferConverter: @unchecked Sendable {
    private let lock = NSLock()
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        lock.lock()
        defer { lock.unlock() }

        if converter == nil
            || converter?.inputFormat.isEqual(inputBuffer.format) == false {
            converter = AVAudioConverter(from: inputBuffer.format, to: outputFormat)
            converter?.primeMethod = .none
        }
        guard let converter else {
            throw ConverterError.creationFailed
        }

        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = max(1, AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)))
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else {
            throw ConverterError.allocationFailed
        }

        let source = ConverterInput(buffer: inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            guard !source.wasSupplied else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            source.wasSupplied = true
            inputStatus.pointee = .haveData
            return source.buffer
        }
        if status == .error {
            throw ConverterError.failed(conversionError?.localizedDescription ?? "unknown")
        }
        return outputBuffer
    }

    private enum ConverterError: Error {
        case creationFailed
        case allocationFailed
        case failed(String)
    }

    private final class ConverterInput: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        var wasSupplied = false
        init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }
}
