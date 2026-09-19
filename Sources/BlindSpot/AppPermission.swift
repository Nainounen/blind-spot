import AppKit
import AVFoundation
import ApplicationServices
import ScreenCaptureKit
import Speech

/// Triggers Apple's official TCC prompts. We cannot grant these ourselves —
/// the user still has to click Allow or flip the toggle. Calling the request
/// APIs is what *registers* BlindSpot in the System Settings list, so the app
/// is already there when the pane opens instead of requiring a manual search.
enum AppPermission {
    case accessibility
    case screenRecording
    case microphone
    case speechRecognition

    var isGranted: Bool {
        switch self {
        case .accessibility:     return AXIsProcessTrusted()
        case .screenRecording:   return CGPreflightScreenCaptureAccess()
        case .microphone:        return AVAudioApplication.shared.recordPermission == .granted
        case .speechRecognition: return SFSpeechRecognizer.authorizationStatus() == .authorized
        }
    }

    var settingsURL: URL {
        let spec: String
        switch self {
        case .accessibility:
            spec = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording:
            spec = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone:
            spec = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            spec = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        }
        return URL(string: spec)!
    }

    /// Show Apple's consent dialog when TCC will still present one. If the user
    /// already denied, the dialog is suppressed — open the matching Settings
    /// pane instead, where this app is listed because of the earlier request.
    @MainActor
    func request() async {
        guard !isGranted else { return }
        // Accessory apps swallow permission sheets unless we are frontmost.
        NSApp.activate(ignoringOtherApps: true)

        switch self {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        case .screenRecording:
            await requestScreenRecording()
        case .microphone:
            if AVAudioApplication.shared.recordPermission == .denied {
                openSettings()
            } else {
                _ = await AVAudioApplication.requestRecordPermission()
            }
        case .speechRecognition:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized:
                break
            case .denied, .restricted:
                openSettings()
            default:
                _ = await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
                }
            }
        }

        NotificationCenter.default.post(name: .permissionsDidChange, object: nil)
    }

    /// `CGRequestScreenCaptureAccess()` is a no-op on recent macOS. Touching
    /// `SCShareableContent` is what actually presents the Screen Recording prompt.
    @MainActor
    private func requestScreenRecording() async {
        _ = CGRequestScreenCaptureAccess()
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            print("[BlindSpot] Screen recording request: \(error.localizedDescription)")
            openSettings()
        }
    }

    func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    /// Screen Recording TCC is cached for the process lifetime on many macOS
    /// versions — after enabling it in System Settings the app must relaunch.
    /// This is a restart of the same .app, not a rebuild.
    static func relaunch() {
        let appURL = runningBundleURL()
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { running, error in
            DispatchQueue.main.async {
                if running == nil {
                    print("[BlindSpot] Relaunch via NSWorkspace failed: \(error?.localizedDescription ?? "unknown")")
                    launchDetached(appURL)
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// Prefer the running .app (BlindSpot-Dev.app), not the inner symlink to `.build/debug`.
    private static func runningBundleURL() -> URL {
        if let url = NSRunningApplication.current.bundleURL, url.pathExtension == "app" {
            return url
        }
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.bundleURL
        }
        if let exe = Bundle.main.executableURL {
            let app = exe.deletingLastPathComponent() // MacOS
                .deletingLastPathComponent()          // Contents
                .deletingLastPathComponent()          // .app
            if app.pathExtension == "app" { return app }
        }
        return Bundle.main.bundleURL
    }

    /// `open -n` returns once LaunchServices has spawned the new instance, so it
    /// survives our subsequent terminate. (`open -a` takes a name, not a path,
    /// and without `-n` it only activates this process — which we then quit.)
    private static func launchDetached(_ appURL: URL) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-n", appURL.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }
}

extension Notification.Name {
    static let permissionsDidChange = Notification.Name("BlindSpotPermissionsDidChange")
}
