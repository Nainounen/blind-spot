# BlindSpot — Project Guide for Claude

## What this is

BlindSpot is a macOS menu-bar app that answers questions about any selected text. The user selects text anywhere on screen, presses **⌘⇧Space**, and a floating AI response streams in an overlay. The overlay is invisible to screen recorders and screenshot tools (NSPanel with `.sharingType = .none`).

Built in Swift using SwiftUI + AppKit. No Xcode project — pure Swift Package Manager.

## How to build and run locally

```bash
swift build                        # debug build
pkill BlindSpot; .build/debug/BlindSpot &   # kill old, launch fresh
```

Releases are built by CI via `make-release.sh` and published automatically when `VERSION` is bumped and pushed to `main`.

## Releasing

Bump `VERSION` (e.g. `1.0.7` → `1.0.8`), commit, and push to `main`. GitHub Actions builds a universal `.app`, packages it as a DMG, and publishes a GitHub Release. The Homebrew tap updates automatically.

## Architecture

`AppDelegate` coordinates five controllers:

| Controller | Role |
|---|---|
| `HotkeyManager` | Global hotkey (⌘⇧Space) via CGEvent tap |
| `OverlayWindowController` | Floating NSPanel, streaming AI response, conversation history |
| `MenuBarController` | Status bar icon, provider switching, recent history menu |
| `OnboardingWindowController` | First-launch wizard (provider → API key → accessibility) |
| `SettingsWindowController` | Settings panel (provider, API key, model, hotkey, system prompt) |

## Key design decisions

- **`.accessory` activation policy throughout** — no Dock icon, no menu bar. Keyboard shortcuts in text fields require `NSApp.mainMenu` to be set with an Edit menu (done in `AppDelegate.applicationDidFinishLaunching`).
- **`PasteableKeyField`** — custom `NSTextField` subclass that routes Cmd+V/C/X/A/Z manually. Used in API key fields and the follow-up bar. For multi-line text (system prompt), use SwiftUI's native `TextEditor` — it handles appearance correctly in release builds.
- **Overlay privacy** — `NSPanel.sharingType = .none` makes it invisible to screen capture at the system level.
- **Non-activating panel** — `OverlayWindowController` uses `.nonactivatingPanel` so the overlay appears without stealing focus from the frontmost app. ESC dismissal uses `NSEvent.addGlobalMonitorForEvents` because local monitors don't fire when another app is frontmost.
- **Conversation** — `OverlayWindowController` maintains a `[ConversationMessage]` array across turns. `HistoryStore` persists the last 10 first-turn exchanges to UserDefaults and posts `.historyDidUpdate` notifications.

## AI providers

| Provider | Default model | API endpoint |
|---|---|---|
| OpenAI | gpt-4o | api.openai.com |
| Anthropic | claude-sonnet-4-5 | api.anthropic.com |
| Gemini | gemini-2.5-flash | generativelanguage.googleapis.com |
| DeepSeek | deepseek-chat | api.deepseek.com (OpenAI-compatible) |
| Grok | grok-3 | api.x.ai/v1 (OpenAI-compatible) |
| Ollama | llama3.2 | localhost:11434 |

Anthropic requires special message format: system prompt goes in a top-level `system` field, not inside the messages array. Gemini maps `assistant` role to `"model"` and uses a `systemInstruction` field. The rest use the standard OpenAI format.

## Config and storage

- API keys: `~/.config/blind-spot/keys/<provider>` (0o600 permissions)
- System prompt: `~/.config/blind-spot/system-prompt.txt`
- Named prompts: `~/.config/blind-spot/prompts/<name>.txt`
- UserDefaults: provider choice, model overrides, hotkey, onboarding flag
- Config reads in precedence: env vars → UserDefaults → file storage

## File map

```
Sources/BlindSpot/
  AppDelegate.swift              — app lifecycle, hotkey wiring, Edit menu
  Config.swift                   — Provider enum, static config reads
  PreferencesStore.swift         — @Observable prefs, Combine publishers
  AIService.swift                — streaming query, all provider adapters
  ConversationMessage.swift      — Role enum + message struct
  HistoryStore.swift             — persistence, max 10 entries
  OverlayWindowController.swift  — panel lifecycle, conversation, ESC monitor
  OverlayView.swift              — SwiftUI overlay UI, markdown renderer, OverlayViewModel
  MenuBarController.swift        — NSStatusItem, provider submenu, history submenu
  OnboardingView.swift           — 5-step wizard + OnboardingWindowController
  SettingsView.swift             — settings panel + SettingsWindowController
  PasteableKeyField.swift        — NSTextField wrapper with keyboard shortcut support
  HotkeyManager.swift            — CGEvent tap, hotkey recording
  TextCapture.swift              — AX API selected text extraction
  OllamaService.swift            — model discovery at localhost:11434
```
