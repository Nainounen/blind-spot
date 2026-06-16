# Contributing to BlindSpot

Thanks for your interest. BlindSpot is a SwiftUI + AppKit macOS app built with Swift Package Manager (no Xcode project). This document covers local development, architecture, common pitfalls, and the release pipeline.

---

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools: `xcode-select --install`
- Swift 5.9 or later
- [`create-dmg`](https://github.com/create-dmg/create-dmg) for release DMG packaging: `brew install create-dmg`

---

## Quick start

```bash
git clone https://github.com/Nainounen/blind-spot.git
cd blind-spot
swift build
pkill BlindSpot; .build/debug/BlindSpot &
```

The app runs as a menu-bar item (no Dock icon). Press **⌘⇧Space** over selected text to trigger it.

### Run with env vars

```bash
./scripts/run.sh                           # default (OpenAI)
./scripts/run.sh --provider anthropic
./scripts/run.sh --provider ollama --model mistral
./scripts/run.sh my-prompt --provider deepseek
```

Prompts live at `~/.config/blind-spot/prompts/<name>.txt`. `scripts/run.sh` reads API keys from `~/.config/blind-spot/keys/<provider>` or prompts interactively.

---

## Architecture

`AppDelegate` coordinates five controllers:

| Controller | Role |
|---|---|
| `HotkeyManager` | Global hotkey via CGEvent tap, hotkey recording |
| `CommandPanelController` | Borderless NSPanel, two-column Raycast-style UI, conversation streaming, ESC/global key monitors |
| `MenuBarController` | NSStatusItem icon, profile switcher submenu, conversation history submenu |
| `OnboardingWindowController` | First-launch wizard (provider → API key → accessibility, 5 steps) |
| `SettingsWindowController` | Settings panel with Profiles, API Keys, Preferences, Hotkeys tabs |

### Activation policy

BlindSpot uses `.accessory` activation policy throughout — no Dock icon, no App Switcher entry. The Settings window temporarily switches to `.regular` while open so standard NSWindow controls render correctly.

### Key design decisions

- **`.accessory` + Edit menu**: Keyboard shortcuts (Cmd+V/C/X/A/Z) don't work in text fields by default in `.accessory` apps. A hidden `NSApp.mainMenu` with an Edit menu is registered in `AppDelegate.applicationDidFinishLaunching`.
- **Streaming stop / Ctrl+C**: `CommandPanelController` shows a stop button while streaming. The local key monitor intercepts Ctrl+C to cancel the active `Task`.
- **Overlay privacy**: `NSPanel.sharingType = .none` makes the panel invisible to screen capture at the compositor level — it does not appear in screenshots, ScreenCaptureKit recordings, or video calls.
- **Non-activating panel**: The command panel appears without stealing focus from the frontmost app. ESC dismissal uses both `NSEvent.addLocalMonitorForEvents` (when the panel is key) and `addGlobalMonitorForEvents` (when another app is frontmost). Both check `panel?.attachedSheet` before acting so confirmation dialogs handle ESC themselves.
- **ESC with sheets**: When an alert or `.confirmationDialog` is attached to the panel, the ESC monitors pass through instead of hiding the panel — the sheet handles ESC for cancellation.
- **Enter to confirm dialogs**: Removing `.destructive` role from a confirmation dialog button makes macOS treat it as the default, so Enter triggers it.
- **Shift+Enter in input**: The follow-up bar uses native SwiftUI `TextEditor` with `.onKeyPress(keys: [.return], phases: .down)`. Plain Enter submits; Shift+Enter returns `.ignored` so the system inserts a newline.

---

## Known pitfalls

### Invisible text in NSTextView within `.accessory` panels

**The #1 bug you'll hit.** Any `NSViewRepresentable` wrapping `NSTextView` renders with invisible (or wrong-color) text in release builds when the app is in `.accessory` activation policy. Manual color fixes (`textColor = .textColor`, `viewDidChangeEffectiveAppearance`, `refreshTextColors()`) are unreliable — the NSHostingView appearance context is wrong at render time and the resolved color gets baked into the attributed string.

**Fix:** Use native SwiftUI `TextEditor` + `.scrollContentBackground(.hidden)` for multi-line inputs in `.accessory` panels. For windows that switch to `.regular` (like Settings), call `NSApp.setActivationPolicy(.regular)` **before** creating the `NSWindow` + `NSHostingView`.

### Slider tint in release builds

Sliders may appear plain grey instead of accent-colored in release builds. This is a known cosmetic issue — the sliders function correctly, only the track color is affected. Not yet resolved.

---

## Project structure

```
Sources/BlindSpot/
  AppDelegate.swift              — app lifecycle, hotkey wiring, Edit menu, Sparkle setup
  Config.swift                   — Provider enum, static config reads, env var precedence
  PreferencesStore.swift         — @Observable prefs, Combine publishers, key management
  AIService.swift                — streaming query, all provider adapters (OpenAI, Anthropic, Gemini, DeepSeek, Grok, OpenRouter, Ollama)
  AIProfile.swift                — Profile model (provider, model, system prompt, temp, tokens, thinking), ProfilesStore singleton, ReasoningEffort enum
  AutoAnswerService.swift        — [BETA] AX-based exam auto-answer (⌘⌥A / ⌘⌥⇧A)
  ConversationMessage.swift      — Role enum + message struct
  ConversationStore.swift        — Conversation persistence, CRUD, folders, export
  CommandPanelController.swift   — Floating command panel NSWindow, streaming lifecycle, key monitors
  CommandPanelView.swift         — SwiftUI command panel UI, markdown renderer, sidebar, conversation area
  CommandPanelViewModel.swift    — @Observable conversation state + turn model
  OverlayWindowController.swift  — Legacy floating overlay (still used alongside command panel)
  OverlayView.swift              — Legacy SwiftUI overlay UI + OverlayViewModel
  MenuBarController.swift        — NSStatusItem, provider submenu, conversation history submenu
  OnboardingView.swift           — 5-step wizard + OnboardingWindowController
  SettingsView.swift             — Settings panel (Profiles, API Keys, Preferences, Hotkeys) + SettingsWindowController
  PasteableKeyField.swift        — NSTextField wrapper with keyboard shortcut support for .accessory apps
  PasteableTextEditor.swift      — NSTextView wrapper for multi-line input (prefer TextEditor where possible)
  ProviderIcon.swift             — Provider logo from asset catalog, SF Symbol fallback
  HotkeyManager.swift            — CGEvent tap, hotkey recording
  Hotkey.swift                   — Hotkey model + display helpers
  HotkeyRecorder.swift           — SwiftUI key recording control
  TextCapture.swift              — AX API selected text extraction, Chromium fallback
  OllamaService.swift            — Model discovery at localhost:11434 (/api/tags)
```

### Scripts

| Script | Purpose |
|---|---|
| `scripts/make-app.sh <version>` | Build universal `.app` bundle with Sparkle, resource bundle, icon, Info.plist, ad-hoc signing |
| `scripts/make-release.sh <version>` | Build `.app`, generate DMG background, package as `.dmg` with `create-dmg`, compute sha256 |
| `scripts/make-dev-app.sh --run` | Build and launch with AX permissions bootstrap |
| `scripts/run.sh [prompt] [--provider X] [--model Y]` | Build release binary and launch with env vars |
| `scripts/make-icon.swift` | Generate `BlindSpot.icns` from source artwork |
| `scripts/make-dmg-bg.swift` | Render the DMG background image |

---

## Data models

### AIProfile (`AIProfile.swift`)

Each profile configures: provider, model, system prompt, max output tokens, temperature, thinking/reasoning mode. Stored as a JSON array at `~/.config/blind-spot/profiles.json` (mode 0600). Active profile tracked via UserDefaults key `activeProfileId`.

### Conversation (`ConversationStore.swift`)

Every exchange is a `Conversation` with multi-turn `[ConversationMessage]` history. Stored as individual JSON files at `~/.config/blind-spot/conversations/<uuid>.json`. Conversations lock to the profile active at creation time (`profileId` never changes). Auto-pruned to 100 max. Legacy `HistoryStore` entries are migrated on first launch.

### Thinking / reasoning mode

Profiles can enable a thinking/reasoning mode via `thinkingEnabled` + `reasoningEffort` (low/medium/high/max). The API format varies by provider:

| Provider | Format |
|---|---|
| OpenAI | `"reasoning_effort": "<low\|medium\|high>"` |
| Anthropic | `"thinking": {"type": "adaptive", "effort": "<low\|medium\|high>"}` |
| DeepSeek | `"reasoning_effort": "<low\|medium\|high\|max>"` + `"thinking": {"type": "enabled"}` |
| Grok / OpenRouter | Same as OpenAI: `"reasoning_effort"` |

Temperature is automatically disabled for providers that don't support it in thinking mode (OpenAI, DeepSeek, Grok, OpenRouter). Anthropic is the exception — temperature still applies alongside thinking.

---

## AI providers

BlindSpot supports 7 providers through a unified streaming interface in `AIService.swift`:

| Provider | Default model | API endpoint | Thinking support |
|---|---|---|---|
| OpenAI | gpt-4o | api.openai.com | Yes |
| Anthropic | claude-sonnet-4-5 | api.anthropic.com | Yes |
| Gemini | gemini-2.5-flash | generativelanguage.googleapis.com | No |
| DeepSeek | deepseek-chat | api.deepseek.com (OpenAI-compatible) | Yes |
| Grok | grok-3 | api.x.ai/v1 (OpenAI-compatible) | Yes |
| OpenRouter | openai/gpt-4o | openrouter.ai (OpenAI-compatible) | Yes |
| Ollama | llama3.2 | localhost:11434 | No |

Provider-specific format quirks:
- **Anthropic**: System prompt goes in a top-level `system` field, not inside the messages array. Role is `assistant`, not `"model"`.
- **Gemini**: Maps `assistant` role to `"model"`, uses a `systemInstruction` field.
- **All others**: Standard OpenAI chat-completions format.

---

## Adding a provider

1. Add a case to the `Provider` enum in `Config.swift`
2. Fill in all computed properties: `displayName`, `defaultModel`, `requiresKey`, `supportsThinking`, `thinkingDescription`, `signupURL`, `logoImageName`, `fallbackIcon`, `suggestedModels`
3. Add the provider logo SVG to `Sources/BlindSpot/Resources/` (named `provider-<rawValue>.svg`) and register it in the asset catalog
4. Add API key env var support in `Config.apiKey`
5. Add the query method in `AIService.swift` (if the provider's API format differs from OpenAI-compatible)
6. Add the provider to the onboarding wizard (already handled by `Provider.allCases`)

---

## Adding a Chromium-based browser

BlindSpot reads selections via the macOS Accessibility API. Some Chromium-based browsers don't expose a full AX bridge — `TextCapture` falls back to the find-pasteboard (`Cmd+E`) for these. To add support:

```bash
osascript -e 'id of app "YourBrowser"'
```

Add the bundle ID to `chromiumBundleIDs` in `TextCapture.swift`.

---

## Config precedence

All config reads follow this order:

1. Environment variables (highest priority)
2. UserDefaults
3. File storage (`~/.config/blind-spot/`)

| Setting | Env var |
|---|---|
| Provider | `BLIND_SPOT_PROVIDER` |
| Model | `BLIND_SPOT_MODEL` |
| API key | `BLIND_SPOT_API_KEY` (or provider-specific: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `DEEPSEEK_API_KEY`, `XAI_API_KEY`, `OPENROUTER_API_KEY`) |
| Prompt | `BLIND_SPOT_PROMPT` (named prompt file to load) |
| Demo mode | `BLIND_SPOT_DEMO=1` (disables screen-capture exclusion) |

---

## Releasing

Releases are fully automated. To ship a new version:

1. Update the `VERSION` file with the new version number (e.g. `1.0.2` → `1.0.3`)
2. Commit and push to `main`

GitHub Actions:
- Reads `VERSION`
- Skips if a GitHub Release for that version already exists
- Builds a universal `BlindSpot.app` (arm64 + x86_64) with Sparkle.framework bundled
- Packages it as `BlindSpot-<version>.dmg` with a drag-to-Applications layout
- Generates and commits the Sparkle `appcast.xml` (signed with the `SPARKLE_PRIVATE_KEY` secret)
- Creates a GitHub Release with the DMG and sha256 attached
- Updates the Homebrew tap (`Nainounen/homebrew-blindspot`) if `HOMEBREW_TAP_TOKEN` and `HOMEBREW_TAP_REPO` are configured

To test the DMG locally before merging:

```bash
brew install create-dmg
./scripts/make-release.sh <version>
open dist/BlindSpot-<version>.dmg
```

### Commit tags

Appcast update commits use `[skip ci]` in the message to avoid triggering redundant CI runs:

```
chore: update appcast for v2.0.8 [skip ci]
```

---

## Keyboard shortcuts

| Shortcut | Context | Action |
|---|---|---|
| ⌘⇧Space | Global | Open panel / query selected text |
| ⌘N | Panel | New conversation |
| ⌘K / ⌘F | Panel | Focus sidebar search |
| ⌘W / ESC | Panel | Close panel |
| Ctrl+C | Panel | Cancel active stream |
| ⌘⌥A | Global | Auto-answer current exam question (beta) |
| ⌘⌥⇧A | Global | Auto-answer all questions on page (beta) |
| ⌘⌥Q | Global | Panic quit |

---

## Code style

- Swift only, targeting macOS 14+
- No third-party dependencies — Apple frameworks + Sparkle (via SPM) only
- English for all identifiers and comments
- No triple-quoted block comments (`/* … */`)
- No emojis in code
- Follow existing patterns — match the surrounding code's naming, comment density, and structure
- Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`

---

## Storage layout

```
~/.config/blind-spot/
  profiles.json                 — JSON array of AIProfile (mode 0600)
  conversations/
    <uuid>.json                 — one file per Conversation (max 100)
  keys/
    openai                      — API key files (mode 0600)
    anthropic
    gemini
    deepseek
    grok
    openrouter
  system-prompt.txt             — legacy global prompt (migrated to profiles on first launch)
  prompts/
    <name>.txt                  — named prompt files (loaded via BLIND_SPOT_PROMPT env var)
~/Library/Preferences/com.blind-spot.app.plist
                                — activeProfileId, hotkey, model overrides, closeOnFocusLoss, autoCopyLastResponse
```

All data stays on the user's Mac. Nothing is synced or uploaded.

---

## Opening a pull request

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Test the golden path manually: select text → ⌘⇧Space → answer streams correctly
4. Open a PR against `main` with a clear description of what changed and why
5. Keep PRs focused — one concern per PR

There are no automated tests. Manual testing is the minimum bar before opening a PR.

---

## Ideas

See [TODO.md](TODO.md) for planned features and improvements.
