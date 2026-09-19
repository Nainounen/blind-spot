import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Dual-stream capture: microphone (Me) and system audio (Them).
///
/// Buffers are delivered on a background queue. System audio uses an
/// audio-only ScreenCaptureKit stream so other participants in Zoom/Meet/etc.
/// land on a different path from the local mic — no ML diarization required.
final class MeetingAudioCapture: NSObject, @unchecked Sendable {
    enum Channel: Sendable {
        case microphone
        case systemAudio
    }

    var onBuffer: (@Sendable (Channel, AVAudioPCMBuffer) -> Void)?

    private var engine: AVAudioEngine?
    private var stream: SCStream?
    private var streamOutput: SystemAudioOutput?
    private let audioQueue = DispatchQueue(label: "com.blindspot.meeting-audio")

    func start() async throws {
        try startMicrophone()
        do {
            try await startSystemAudio()
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil

        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        streamOutput = nil
    }

    // MARK: - Microphone

    private func startMicrophone() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.onBuffer?(.microphone, buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
    }

    // MARK: - System audio

    private func startSystemAudio() async throws {
        if !CGPreflightScreenCaptureAccess() {
            let granted = CGRequestScreenCaptureAccess()
            if !granted {
                throw CaptureError.screenRecordingDenied
            }
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        // Minimal video config — we never consume screen frames.
        config.width = 2
        config.height = 2
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let output = SystemAudioOutput { [weak self] buffer in
            self?.onBuffer?(.systemAudio, buffer)
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioQueue)
        try await stream.startCapture()

        self.streamOutput = output
        self.stream = stream
    }

    enum CaptureError: LocalizedError {
        case screenRecordingDenied
        case noDisplay

        var errorDescription: String? {
            switch self {
            case .screenRecordingDenied:
                return "Screen Recording permission is required to capture meeting audio."
            case .noDisplay:
                return "No display available for system audio capture."
            }
        }
    }
}

// MARK: - SCStream output

private final class SystemAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void

    init(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let pcm = AVAudioPCMBuffer.from(sampleBuffer) else { return }
        onBuffer(pcm)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[BlindSpot] System audio capture stopped: \(error.localizedDescription)")
    }
}

// MARK: - CMSampleBuffer → PCM

private extension AVAudioPCMBuffer {
    /// Handles both interleaved and non-interleaved SCStream layouts.
    /// macOS 26 often delivers Float32 stereo as two separate buffers.
    static func from(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return nil }
        let avFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: avFormat,
            frameCapacity: AVAudioFrameCount(numSamples)
        ) else { return nil }

        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(numSamples),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return pcmBuffer
    }
}
