# BlindSpot

A macOS utility that reads your selected text with a global hotkey, sends it to an AI, and shows the answer in a formatted floating overlay — completely invisible to screen recorders.

## How it works

- Press **Cmd+Shift+Space** over any selected text
- BlindSpot captures the selection via the macOS Accessibility API (no clipboard pollution)
- The text is sent to your chosen AI provider and the response streams back in a Markdown overlay
- The overlay uses `NSWindowSharingNone` — it is **excluded from all screen capture** at the compositor level

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)
- An API key for the provider you want to use (not needed for Ollama)

## Quick start

```bash
git clone https://github.com/Nainounen/blind-spot.git
cd blind-spot
./run.sh
```

On first run you are prompted for your API key. It is saved to `~/.config/blind-spot/keys/<provider>` (mode 600) and never stored in the repo.

Grant **Accessibility** permission when macOS asks — required for the global hotkey and text capture.

## Choosing an AI provider

```bash
./run.sh                            # OpenAI gpt-4o (default)
./run.sh --provider anthropic       # Anthropic claude-opus-4-5
./run.sh --provider ollama          # Local Ollama (no API key)
```

| Flag | Short | Values |
|---|---|---|
| `--provider` | `-p` | `openai` · `anthropic` · `ollama` |
| `--model` | `-m` | Any model name supported by the provider |

```bash
./run.sh --provider anthropic --model claude-haiku-4-5
./run.sh --provider ollama --model mistral
./run.sh --provider openai --model gpt-4o-mini
```

Run `./run.sh --help` for the full usage reference.

### Provider defaults

| Provider | Default model | API key location |
|---|---|---|
| `openai` | `gpt-4o` | `~/.config/blind-spot/keys/openai` |
| `anthropic` | `claude-opus-4-5` | `~/.config/blind-spot/keys/anthropic` |
| `ollama` | `llama3.2` | None (local) |

Keys are saved per provider so you can switch freely without re-entering them.

### Using environment variables

```bash
BLIND_SPOT_API_KEY=sk-...  ./run.sh --provider openai
OPENAI_API_KEY=sk-...      ./run.sh            # legacy, still works
```

## System prompts

Give the AI a specific role or knowledge base:

```bash
./run.sh my-prompt
./run.sh my-prompt --provider anthropic
```

BlindSpot reads `~/.config/blind-spot/prompts/my-prompt.txt` and sends it as the system message on every request.

### Creating a prompt

```bash
mkdir -p ~/.config/blind-spot/prompts
cp prompts/example.txt ~/.config/blind-spot/prompts/my-prompt.txt
# edit with your instructions
```

See the [`prompts/`](prompts/) folder for the template. Some ideas:

```bash
./run.sh sql        # SQL expert
./run.sh legal      # contract review assistant
./run.sh german     # translate everything to German
```

## Supported browsers

BlindSpot reads selections via the macOS Accessibility API, bypassing JavaScript `oncopy` handlers and clipboard poisoning entirely. For Chromium browsers that lack a full AX bridge (like Dia) it falls back to the macOS find-pasteboard (`Cmd+E`) — still invisible to JavaScript.

| Browser | Support |
|---|---|
| Google Chrome (stable, beta, dev, canary) | Full |
| Brave (stable, beta, nightly) | Full |
| Microsoft Edge (stable, beta, dev, canary) | Full |
| Arc | Full |
| Dia | Full |
| Opera (stable, Next, Developer) | Full |
| Vivaldi (stable, snapshot) | Full |
| Ungoogled Chromium | Full |
| Sidekick | Full |
| Wavebox | Full |
| Firefox | Clipboard fallback |
| Safari | Accessibility API |

### Adding a browser not in the list

Find the bundle ID:

```bash
osascript -e 'id of app "YourBrowser"'
```

Add it to `chromiumBundleIDs` in `Sources/BlindSpot/TextCapture.swift`:

```swift
private let chromiumBundleIDs: Set<String> = [
    // ...existing entries...
    "com.your.browser",
]
```

Rebuild with `./run.sh`.

## Customization

### Max tokens

Edit `Sources/BlindSpot/Config.swift`:

```swift
static let maxTokens = 1024
```

### Hotkey

Edit `Sources/BlindSpot/HotkeyManager.swift`. The default is `Cmd+Shift+Space` (keyCode 49).

Find keyCodes with the free [Key Codes](https://apps.apple.com/app/key-codes/id414568915) app or via `IOHIDUsageTables`.

### Overlay appearance

Edit `Sources/BlindSpot/OverlayView.swift`. Responses render as Markdown:

- `**bold**`, `*italic*`, `` `code` ``
- `## headings`
- `- bullet lists`
- ` ```code blocks``` `

## Privacy

- API keys are stored locally in `~/.config/blind-spot/keys/` with mode 600
- System prompts are stored locally in `~/.config/blind-spot/prompts/`
- Selected text is sent to the API of your chosen provider — subject to their respective privacy policy
- The overlay is excluded from screen recording at the compositor level (`NSWindowSharingNone`)
- BlindSpot runs as a background accessory process with no Dock icon

## Building manually

```bash
swift build -c release
BLIND_SPOT_PROVIDER=openai BLIND_SPOT_API_KEY=sk-... .build/release/BlindSpot
```

## License

MIT
