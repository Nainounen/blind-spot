# BlindSpot

AI answers for anything you select — completely invisible to screen recorders.

Press **⌘⇧Space** over any selected text. An answer streams back in a floating overlay that no screen recording tool can capture.

---

## Install

### Download (no terminal needed)

1. Go to the [latest release](https://github.com/Nainounen/blind-spot/releases/latest)
2. Download `BlindSpot-<version>.dmg`
3. Double-click the DMG — a window opens with the app and an **Applications** shortcut
4. **Drag `BlindSpot` onto the `Applications` folder**
5. **First launch only**: open `Applications`, **right-click `BlindSpot` → Open → Open**

#### Why the right-click on first launch?

The app isn't notarized with Apple yet (that requires a paid Apple Developer
account), so macOS Gatekeeper doesn't recognise it. The right-click → Open
dance bypasses that warning **once**; after that, double-clicking works
forever. The app is universal (Apple Silicon + Intel) and the source code
is right here — you can verify it before running.

### Homebrew (terminal users)

```bash
brew tap Nainounen/blindspot
brew install --cask blindspot
open -a BlindSpot
```

Homebrew installs `BlindSpot.app` into `/Applications` automatically *and*
strips the Gatekeeper warning, so there's no right-click step. Updates:

```bash
brew update && brew upgrade --cask blindspot
```

> Requires the tap repo `Nainounen/homebrew-blindspot` to exist. See
> [Publishing a release](#publishing-a-release) below for the one-time setup.

### Build from source (developer)

```bash
git clone https://github.com/Nainounen/blind-spot.git
cd blind-spot
./make-app.sh           # produces BlindSpot.app in the repo root
open BlindSpot.app
# or, to run directly without packaging:
./run.sh
```

---

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools — `xcode-select --install`

---

## First launch — onboarding

When BlindSpot starts for the first time, a setup wizard guides you through:

1. **Choose your AI** — OpenAI, Anthropic, Gemini, or Ollama (local)
2. **API key** — paste your key; it's saved locally and never leaves your Mac
3. **Accessibility permission** — required to read selected text and listen for the hotkey
4. **Done** — the ✦ icon appears in your menu bar

After setup, just select text anywhere and press **⌘⇧Space**.

---

## Menu bar

The **✦** icon in the menu bar lets you:

- Switch AI provider on the fly
- Open Settings to change the model or API key
- Quit

---

## Choosing a provider

| Provider | Default model | API key |
|---|---|---|
| **OpenAI** | `gpt-4o` | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| **Anthropic** | `claude-opus-4-5` | [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) |
| **Gemini** | `gemini-2.5-flash` | [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey) |
| **DeepSeek** | `deepseek-chat` | [platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys) |
| **Ollama** | `llama3.2` | None — runs locally |

API keys are stored at `~/.config/blind-spot/keys/<provider>` (mode 600).

### Advanced — CLI flags

```bash
./run.sh --provider anthropic
./run.sh --provider ollama --model mistral
./run.sh my-prompt --provider openai --model gpt-4o-mini
./run.sh --help
```

---

## System prompts

Give the AI a fixed role or knowledge base:

```bash
mkdir -p ~/.config/blind-spot/prompts
cp prompts/example.txt ~/.config/blind-spot/prompts/my-prompt.txt
# edit the file, then:
./run.sh my-prompt
```

See [`prompts/example.txt`](prompts/example.txt) for a starting template.

---

## Supported browsers

BlindSpot reads selections via the macOS Accessibility API, bypassing JavaScript copy handlers entirely. For Chromium browsers without a full AX bridge it uses the find-pasteboard (`Cmd+E`) — JavaScript cannot see this.

| Browser | Support |
|---|---|
| Chrome (stable / beta / dev / canary) | Full |
| Brave (stable / beta / nightly) | Full |
| Microsoft Edge (stable / beta / dev / canary) | Full |
| Arc · Dia | Full |
| Opera · Vivaldi | Full |
| Ungoogled Chromium · Sidekick · Wavebox | Full |
| Firefox | Clipboard fallback |
| Safari | Accessibility API |

**Add your browser** — find its bundle ID and add it to `chromiumBundleIDs` in `TextCapture.swift`:

```bash
osascript -e 'id of app "YourBrowser"'
```

---

## Customization

| What | Where |
|---|---|
| Max tokens | `Config.swift` → `maxTokens` |
| Hotkey | `HotkeyManager.swift` → `virtualKey` / `requiredFlags` |
| Overlay appearance | `OverlayView.swift` (full Markdown rendering) |

---

## Publishing a release

The release pipeline ships `BlindSpot.app` to users via a Homebrew Cask hosted
in a separate tap repo, automated by GitHub Actions.

### One-time setup

1. **Create the tap repo.** It must be named exactly `homebrew-blindspot`
   (the `homebrew-` prefix is required by Homebrew).
   ```bash
   gh repo create Nainounen/homebrew-blindspot --public \
     --description "Homebrew tap for BlindSpot"
   ```
   Seed it with the cask from this repo:
   ```bash
   git clone https://github.com/Nainounen/homebrew-blindspot.git
   mkdir -p homebrew-blindspot/Casks
   cp Casks/blindspot.rb homebrew-blindspot/Casks/blindspot.rb
   cd homebrew-blindspot && git add . && git commit -m "initial cask" && git push
   ```
2. **Create a fine-grained PAT** with `Contents: write` on
   `Nainounen/homebrew-blindspot`. Add it to this repo as the
   `HOMEBREW_TAP_TOKEN` **secret** and add the variable
   `HOMEBREW_TAP_REPO=Nainounen/homebrew-blindspot` under repo **variables**.
   Without these the release workflow still publishes the GitHub Release; it
   just skips the cask bump.

### Cutting a release

Locally:
```bash
./make-release.sh 1.0.1   # builds dist/BlindSpot-1.0.1.dmg (universal) + .sha256
open dist/BlindSpot-1.0.1.dmg   # optional: preview the drag-to-Applications UI
git tag v1.0.1 && git push origin v1.0.1
```

The push triggers `.github/workflows/release.yml`, which:

1. Builds a universal `BlindSpot.app` (arm64 + x86_64) on a `macos-14`
   runner via `make-release.sh`.
2. Packages it as `BlindSpot-1.0.1.dmg` with the standard
   drag-to-`Applications` Finder layout.
3. Creates a GitHub Release `v1.0.1` with the DMG attached and an install
   blurb in the release notes.
4. Rewrites `Casks/blindspot.rb` in `homebrew-blindspot` with the new
   `version` + `sha256` and pushes a `blindspot: bump to 1.0.1` commit.

Users then either re-download the new DMG from the releases page, or run
`brew upgrade --cask blindspot` to pick up the new build.

### Future: in-app auto-updates with Sparkle

Neither the DMG download nor `brew upgrade` updates the app on its own —
the user has to remember to run them. For silent in-app auto-updates (the
way Rectangle, Raycast, etc. update themselves) integrate
[Sparkle](https://sparkle-project.org). It needs:

- An [Apple Developer Program](https://developer.apple.com/programs/)
  membership to obtain a Developer ID certificate (required for notarization
  — without it Sparkle's update verification fails).
- An EdDSA keypair generated via Sparkle's `generate_keys` tool. The public
  half goes into `Info.plist` as `SUPublicEDKey`; the private half stays in
  Keychain / GitHub Secrets.
- An appcast XML hosted somewhere (e.g. GitHub Pages). Sparkle's
  `generate_appcast` tool produces it from a folder of `.dmg` files,
  exactly what this project already builds.
- `import Sparkle` + an `SPUStandardUpdaterController` wired into
  `AppDelegate`.

Until that's in place, the DMG download or `brew upgrade --cask blindspot`
is the supported update path.

---

## Privacy

- API keys are stored locally at `~/.config/blind-spot/keys/` (mode 600)
- System prompts are stored locally at `~/.config/blind-spot/prompts/`
- Selected text is sent to your chosen provider's API — subject to their privacy policy
- The overlay is excluded from screen recording at the compositor level (`NSWindowSharingNone`)
- BlindSpot runs as a background accessory with no Dock icon

---

## License

MIT
