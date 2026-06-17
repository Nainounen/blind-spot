# BlindSpot — TODO / Ideas

## Known issues

- **DeepSeek V4 vision**: Returns HTTP 400 when sending images via the OpenAI-compatible endpoint. The API docs claim support for `image_url` content blocks, but in practice the request is rejected. Possibly a model name issue (deepseek-v4-flash vs deepseek-chat), a beta limitation, or a format quirk. Needs further investigation — test with `deepseek-v4-pro` or try the Anthropic-compatible endpoint.

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
