# BlindSpot — TODO / Ideas

## Visual Context Screenshot (⌘⇧⌥Space)

Status: **Done, with known limitations.**

- **Gemini** — confirmed working. The screenshot is sent and the model references visual content.
- **OpenAI (gpt-4o), Anthropic (Claude), Grok** — should work (standard OpenAI image format) but not yet tested.
- **DeepSeek V4** — NOT working. Returns HTTP 400 despite using the documented OpenAI-compatible format. The API docs claim support for `image_url` content blocks on the `/v1/chat/completions` endpoint, but in practice the request is rejected. Needs further investigation — could be a model name issue (deepseek-v4-flash vs deepseek-chat) or a beta limitation on the vision endpoint.
- **Ollama** — not supported (text-only).

## Features

- **Same-panel follow-up**: When the command panel is already open, pressing the hotkey again should append to the current conversation instead of starting a new one. Both for text and visual context.
- **XS panel profile switching**: The XS compact layout currently has no profile selector. Add a minimal profile switcher.
- **Menu bar profile sync**: The menu bar active profile indicator sometimes goes stale — switching profiles in Settings doesn't update the menu bar.
