# BlindSpot

AI answers for anything you select — completely invisible to screen recorders.

Press **⌘⇧Space** over any selected text. An answer streams back in a floating overlay that no screen recording tool can capture.

---

## Install

### Option A — Homebrew (recommended)

```bash
brew tap Nainounen/blindspot https://github.com/Nainounen/blind-spot
brew install --HEAD blindspot
open "$(brew --prefix)/opt/blindspot/BlindSpot.app"
```

> **Note:** a tap repo `homebrew-blindspot` must exist for `brew tap` to work.
> Until then, use Option B or C below.

### Option B — Pre-built app bundle

1. Clone the repo and run `./make-app.sh`
2. Drag **BlindSpot.app** to `/Applications`
3. Double-click to launch

```bash
git clone https://github.com/Nainounen/blind-spot.git
cd blind-spot
./make-app.sh
open BlindSpot.app
```

> First launch: macOS may show a security warning — go to  
> **System Settings → Privacy & Security → Open Anyway**

### Option C — Terminal (developer)

```bash
git clone https://github.com/Nainounen/blind-spot.git
cd blind-spot
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

## Setting up a Homebrew tap

To let others install with `brew install`, create a public repo named **`homebrew-blindspot`** under your GitHub account and copy `Formula/blindspot.rb` into it. Then:

```bash
brew tap Nainounen/blindspot
brew install --HEAD blindspot
```

Update the `url` and `sha256` in the formula after you create a tagged release.

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
