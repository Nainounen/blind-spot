# BlindSpot — TODO / Ideas

## Known issues

- **DeepSeek V4 vision — NOT SUPPORTED**: DeepSeek's own documentation states "DeepSeek V4 is text-only" (confirmed via Copilot integration guide). Their Anthropic compatibility table explicitly marks `type:"image"` as "Not Supported". The `deepseek-v4-pro` and `deepseek-v4-flash` models at `/v1/chat/completions` do NOT accept images — attempting to send OpenAI-format `image_url` content blocks results in HTTP 400. A separate `deepseek-v4-vision` model exists but is not accessible via the standard chat endpoint and may not be publicly available. Third-party platforms claiming "V4 Vision" (OpenRouter, MindStudio) proxy images through separate vision models, not through DeepSeek V4 itself. `supportsVision` is set to `false` for DeepSeek in Config.swift.

## Done

- [x] Visual context screenshot (⌘⇧⌥Space) — capture area around selection, send to AI
- [x] Same-panel follow-up — hotkey while panel open appends to current conversation
- [x] Configurable hotkey in Settings → Hotkeys
- [x] Per-profile vision model/provider override — route vision via different provider than text
- [x] Configurable screenshot padding + minimum size in Settings → Preferences
- [x] Minimap screenshot preview in Settings
- [x] XS panel profile switcher
- [x] Menu bar profile sync (profilesDidUpdate notification)
- [x] Menu bar panel size presets (XS/Small/Medium/Large)
- [x] Permissions tab showing Accessibility + Screen Recording status
- [x] [image] indicator in chat bubbles
- [x] Sparkle update window activation fix
- [x] Onboarding mentions both shortcuts and permissions
