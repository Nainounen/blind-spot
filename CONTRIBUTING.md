# Contributing to BlindSpot

Thanks for your interest. This document covers how to build the project locally, how releases work, and what to keep in mind when opening a pull request.

---

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools: `xcode-select --install`
- Swift 5.9 or later

---

## Build from source

```bash
git clone https://github.com/Nainounen/blind-spot.git
cd blind-spot
./scripts/make-app.sh   # builds BlindSpot.app in the repo root
open BlindSpot.app
```

For local dev with accessibility permissions (run once, then grant AX in System Settings):

```bash
./scripts/make-dev-app.sh --run
```

To run directly without packaging:

```bash
./scripts/run.sh
./scripts/run.sh --provider anthropic
./scripts/run.sh --provider ollama --model mistral
```

---

## Project structure

```
Sources/BlindSpot/
  AppDelegate.swift          # app lifecycle, menu bar setup
  TextCapture.swift          # reads selected text via Accessibility API
  HotkeyManager.swift        # global hotkey listener
  AIService.swift            # OpenAI, Anthropic, Gemini, DeepSeek streaming
  OllamaService.swift        # local Ollama integration
  OverlayView.swift          # floating answer overlay (screen-capture-excluded)
  SettingsView.swift         # provider + model + API key UI
  OnboardingView.swift       # first-launch setup wizard
  PreferencesStore.swift     # persisted user settings
  Config.swift               # defaults (max tokens, hotkey, etc.)
```

The overlay is excluded from screen capture via `NSWindowSharingNone` set on the window at creation time — no special entitlements required.

---

## Opening a pull request

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Open a PR against `main` with a clear description of what changed and why
4. Keep PRs focused — one concern per PR is easier to review and revert if needed

There are no automated tests at the moment. Manual testing against the golden path (select text → press hotkey → answer appears) is the minimum bar before opening a PR.

---

## Releasing

Releases are fully automated. To ship a new version:

1. Update the `VERSION` file with the new version number (e.g. `1.0.2`)
2. Commit and merge to `main`

GitHub Actions reads `VERSION`, checks whether a release for that version already exists, and if not, builds a universal `BlindSpot.app` (arm64 + x86_64), packages it as a `.dmg`, and publishes a GitHub Release. No manual tagging needed.

To test the DMG locally before merging:

```bash
brew install create-dmg        # one-time
./scripts/make-release.sh      # reads VERSION automatically
open dist/BlindSpot-*.dmg
```

### Homebrew tap

The release workflow also updates `Casks/blindspot.rb` in the `Nainounen/homebrew-blindspot` tap automatically, provided the repo has:

- A `HOMEBREW_TAP_TOKEN` secret (fine-grained PAT with `Contents: write` on the tap repo)
- A `HOMEBREW_TAP_REPO` variable set to `Nainounen/homebrew-blindspot`

Without these, the GitHub Release still publishes — only the cask update is skipped.

---

## Adding a browser

BlindSpot reads selections via the macOS Accessibility API. For Chromium-based browsers without a full AX bridge, it falls back to the find-pasteboard (`Cmd+E`). To add support for a browser not already listed, find its bundle ID:

```bash
osascript -e 'id of app "YourBrowser"'
```

Then add it to `chromiumBundleIDs` in `TextCapture.swift` and open a PR.

---

## Code style

- Swift only, targeting macOS 14+
- No third-party dependencies — the project uses only Apple frameworks
- English for all identifiers and comments
- No triple-quoted block comments
