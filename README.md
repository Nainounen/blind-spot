# BlindSpot

![BlindSpot in action](assets/example.png)

[![Latest Release](https://img.shields.io/github/v/release/Nainounen/blind-spot?style=flat-square&color=7c3aed)](https://github.com/Nainounen/blind-spot/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square&logo=apple)](https://github.com/Nainounen/blind-spot/releases/latest)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)](https://swift.org)
[![License](https://img.shields.io/github/license/Nainounen/blind-spot?style=flat-square)](LICENSE)

AI answers for anything you select — invisible to screen recorders.

Select any text, press **⌘⇧Space**, and an answer streams back in a floating overlay that no screenshot tool or screen recording can capture.

---

## Install

1. Go to the [latest release](https://github.com/Nainounen/blind-spot/releases/latest)
2. Download `BlindSpot-<version>.dmg`
3. Open the DMG and drag **BlindSpot** to **Applications**
4. First launch: right-click → **Open** → **Open**

That last step is a one-time workaround — BlindSpot isn't notarized yet, so macOS flags it the first time. After that, it opens normally.

**Requires macOS 14 Sonoma or later. Works on Apple Silicon and Intel.**

---

## Setup

On first launch, BlindSpot walks you through three steps:

1. **Choose a provider** — OpenAI, Anthropic, Gemini, DeepSeek, Grok, OpenRouter, or Ollama (local, no key needed)
2. **Paste your API key** — saved on your Mac only, never sent anywhere except your chosen provider
3. **Allow Accessibility access** — required to read selected text and listen for the hotkey

Once done, the **✦** icon appears in your menu bar.

---

## What's new in v2

### Raycast-style command panel
The overlay is now a persistent command panel that opens with your hotkey and stays available throughout a session. It has a conversation sidebar, date-grouped history, and a follow-up input — closer to a chat interface than a one-shot overlay.

### AI profiles
Multiple profiles, each with its own provider, model, system prompt, temperature, and token limit. Switch the active profile from the menu bar. Useful for keeping a fast, cheap profile separate from a slower, more thorough one.

### Conversation history
Every exchange is saved and searchable. Conversations can be grouped into folders and exported as Markdown or JSON via right-click.

### Glass-style settings and onboarding
Settings and the onboarding flow use the same visual language as the command panel: thin material background, glass input fields, and consistent typography. The onboarding now shows step progress dots and real provider logos.

### Provider logos
The provider picker shows actual brand icons instead of SF Symbols.

### Copy and auto-copy
Each response has a copy button that is always visible. Settings → Preferences has an option to automatically copy the last response to the clipboard as soon as streaming completes.

### Panel behavior
A setting controls whether the panel closes when you click outside it (Raycast-style) or stays open. ESC dismisses it from any app, even when the panel is not focused.

### Sparkle auto-updates
BlindSpot checks for updates in the background and installs them without leaving the app.

---

## Shortcuts

| Shortcut | Action |
|---|---|
| ⌘⇧Space | Open the panel / query selected text |
| ⌘N | New conversation |
| ⌘K | Focus search |
| ESC | Close the panel |
| ⌘⌥Q | Force-quit |

All shortcuts except ⌘N, ⌘K, and ESC are configurable in Settings.

---

## AI providers

| Provider | Default model | API key |
|---|---|---|
| OpenAI | GPT-4o | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| Anthropic | Claude Sonnet | [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) |
| Google Gemini | Gemini 2.5 Flash | [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey) |
| DeepSeek | DeepSeek Chat | [platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys) |
| xAI Grok | Grok 3 | [console.x.ai](https://console.x.ai) |
| OpenRouter | GPT-4o (via OR) | [openrouter.ai/keys](https://openrouter.ai/keys) |
| Ollama | Llama 3.2 | No key — runs entirely on your Mac |

---

## Privacy

- API keys are stored at `~/.config/blind-spot/keys/` and sent only to your chosen provider
- Selected text goes to your provider's API; their privacy policy applies
- The overlay is excluded from screen capture via `NSWindowSharingNone` at the compositor level — it does not appear in screenshots, ScreenCaptureKit recordings, or video calls (Zoom, Teams, Meet, etc.)
- No Dock icon. No analytics. No data collection.

**Limitation:** The overlay is not protected against `CGDisplayCreateImage` or Accessibility API captures from apps that already hold Screen Recording permission. A physical camera pointed at your screen is also unaffected.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to build from source and submit changes.
