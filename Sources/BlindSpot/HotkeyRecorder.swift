import SwiftUI
import AppKit

/// Click-to-record hotkey field.
///
/// While recording, a local `NSEvent` monitor captures the next keyDown that
/// includes at least one modifier and reports it via `onCapture`. The global
/// `HotkeyManager` tap is paused for the duration via `prefs.isRecordingHotkey`
/// so the user can re-record the same combination they're currently using.
struct HotkeyRecorder: View {
    let hotkey: Hotkey
    @Binding var isRecording: Bool
    var onCapture: (Hotkey) -> Void

    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { isRecording.toggle() }) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isRecording ? Color.purple.opacity(0.12) : Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isRecording ? Color.purple : Color.primary.opacity(0.15),
                                lineWidth: 1
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isRecording {
                Button("Cancel") { isRecording = false }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording { startMonitor() } else { stopMonitor() }
        }
        .onDisappear { stopMonitor() }
    }

    @ViewBuilder
    private var content: some View {
        if isRecording {
            Text("Press hotkey… (Esc to cancel)")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            HStack(spacing: 6) {
                ForEach(Array(hotkey.displaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .font(.title3)
        }
    }

    private func startMonitor() {
        stopMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Esc cancels without saving.
            if event.keyCode == 53 {
                isRecording = false
                return nil
            }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier so we don't bind to bare keys.
            guard !mods.isEmpty else { return nil }
            let hk = Hotkey(keyCode: event.keyCode, modifiers: mods.rawValue)
            onCapture(hk)
            isRecording = false
            return nil
        }
    }

    private func stopMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}
