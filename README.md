# BlindSpot

A macOS utility that reads your selected text with a global hotkey, sends it to an AI, and shows the answer in a floating overlay — completely invisible to screen recorders.

## How it works

- Press **Cmd+Shift+Space** over any selected text
- BlindSpot captures the selection via the macOS Accessibility API (no clipboard pollution)
- The text is sent to OpenAI and the response streams back in a formatted overlay
- The overlay uses `NSWindowSharingNone` — it is **excluded from all screen capture** at the compositor level

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)
- An [OpenAI API key](https://platform.openai.com/api-keys)

## Quick start

```bash
git clone https://github.com/Nainounen/blind-spot.git
cd blind-spot
./run.sh
```

On first run you will be prompted for your OpenAI API key. It is saved to `~/.config/blind-spot/api-key` (mode 600) and never stored in the repo.

Grant **Accessibility** permission when macOS asks (required for the global hotkey and text capture).

## System prompts

You can start BlindSpot with a custom system prompt that gives the AI a specific role or knowledge base:

```bash
./run.sh my-prompt
```

BlindSpot looks for `~/.config/blind-spot/prompts/my-prompt.txt` and prepends it as a system message to every request.

### Creating a prompt

```bash
mkdir -p ~/.config/blind-spot/prompts
cp prompts/example.txt ~/.config/blind-spot/prompts/my-prompt.txt
# edit the file with your instructions
```

See the [`prompts/`](prompts/) folder for the example template and ideas.

### Multiple contexts

Run separate instances (or restart) with different prompts:

```bash
./run.sh sql        # SQL expert
./run.sh legal      # contract review
./run.sh german     # translate to German
```

## Supported browsers

BlindSpot uses the macOS Accessibility API to read selections directly from the browser's rendering engine — bypassing JavaScript `oncopy` handlers and clipboard poisoning entirely.

Supported Chromium-based browsers out of the box:

| Browser | Notes |
|---|---|
| Google Chrome (stable, beta, dev, canary) | Full support |
| Brave (stable, beta, nightly) | Full support |
| Microsoft Edge (stable, beta, dev, canary) | Full support |
| Arc | Full support |
| Dia | Full support (find-pasteboard path) |
| Opera (stable, Next, Developer) | Full support |
| Vivaldi (stable, snapshot) | Full support |
| Ungoogled Chromium | Full support |
| Sidekick | Full support |
| Wavebox | Full support |
| Firefox | Via clipboard fallback |
| Safari | Via Accessibility API |

### Adding your own browser

Open `Sources/BlindSpot/TextCapture.swift` and add the bundle ID to `chromiumBundleIDs`:

```swift
private let chromiumBundleIDs: Set<String> = [
    // ...existing entries...
    "com.your.browser",   // ← add here
]
```

Find a browser's bundle ID with:

```bash
osascript -e 'id of app "YourBrowser"'
```

## Customization

### Model and token limit

Edit `Sources/BlindSpot/Config.swift`:

```swift
static let model     = "gpt-4o"      // any OpenAI chat model
static let maxTokens = 1024
```

### Hotkey

Edit `Sources/BlindSpot/HotkeyManager.swift`. The default is `Cmd+Shift+Space` (keyCode 49).

```swift
// keyCode 49 = Space
// flags: .maskCommand | .maskShift
```

Replace `virtualKey: 49` and `requiredFlags` with your preferred combination.

### Overlay appearance

Edit `Sources/BlindSpot/OverlayView.swift`. The response renders full Markdown:

- `**bold**`, `*italic*`, `` `code` ``
- `## headings`
- `- bullet lists`
- ` ```code blocks``` `

## Privacy

- Your API key is stored locally at `~/.config/blind-spot/api-key` with mode 600
- Prompts are stored locally at `~/.config/blind-spot/prompts/`
- Selected text is sent to the OpenAI API — subject to [OpenAI's privacy policy](https://openai.com/policies/privacy-policy)
- The overlay window is excluded from screen recording (`NSWindowSharingNone`)
- BlindSpot runs as a background accessory app with no Dock icon

## Building manually

```bash
swift build -c release
OPENAI_API_KEY=sk-... .build/release/BlindSpot
```

## License

MIT
