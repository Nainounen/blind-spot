# BlindSpot v2 — Redesign Plan

## Goal

Transform BlindSpot from a simple overlay utility into a Raycast-style AI command palette with persistent conversations, AI profiles, and a modern macOS-native design.

---

## What's changing

### AI Profiles
Users can create, edit, duplicate, and delete profiles. Each profile configures:
- Provider (OpenAI, Anthropic, Gemini, DeepSeek, Grok, OpenRouter, Ollama)
- Model (free text + suggested presets)
- System prompt (per-profile, replaces the old global one)
- Max output tokens (slider 256–16384, default 4096)
- Temperature (slider 0.0–2.0, default 1.0)

On first launch, existing settings are automatically migrated into a "Default" profile.

### Conversation persistence
Every query is now part of a named `Conversation` with full multi-turn history. Conversations are:
- Stored as individual JSON files at `~/.config/blind-spot/conversations/<uuid>.json`
- Sorted by last activity (`updatedAt`)
- Pruned to a max of 100 entries
- Auto-titled from the first user message (up to 60 characters)
- Locked to the profile active at creation time

Old `HistoryStore` entries (UserDefaults `blindSpotHistory`) are migrated to the new format on first launch.

### Raycast-style floating command panel
The old `OverlayWindowController` + `OverlayView` are replaced by `CommandPanelController` + `CommandPanelView`:
- Borderless `NSPanel` with `.ultraThinMaterial` background and 16px rounded corners
- Invisible to screen recorders (`sharingType = .none`) — same as before
- Width: `min(screenWidth * 0.80, 880px)`, height: 560px
- Position: centered horizontally, ~55% from screen top
- Two-column layout: 200px sidebar + main conversation area
- Sidebar: conversation list grouped by Today / Yesterday / This Week / Earlier, with search (Cmd+K) and New button (Cmd+N)
- Main area: turn-by-turn conversation with user query bubbles + streamed markdown responses
- Bottom status bar: active profile name + provider color dot + ESC hint

**Focus behavior:**
- Default: panel stays open when the user clicks in another app (panel lives at `.floating` level). Only ESC / Cmd+W closes it.
- Optional: "Close panel when clicking outside" setting (off by default) — enables Raycast-style dismiss on focus loss.

### Raycast-style Settings window management
- Opening Settings: `setActivationPolicy(.regular)` → BlindSpot appears in the Dock and App Switcher
- Closing Settings: `setActivationPolicy(.accessory)` (50ms delay) → Dock icon disappears, menu bar icon stays
- The background service (hotkey, menu bar) remains alive throughout — no process restart

### Settings: Profiles tab
New first tab in Settings. Shows:
- Left: list of all profiles with + / duplicate / delete toolbar. Active profile shows a checkmark.
- Right: profile editor (name, provider, model, system prompt, max output tokens, temperature, Set as Active, Save, Discard)

### Menu bar updates
- **Profiles submenu:** lists all profiles, checkmark on active, click to switch
- **Recent submenu:** replaced by top 5 conversations from `ConversationStore` (click to open in panel)
- Observes `.conversationsDidUpdate` instead of the old `.historyDidUpdate`

---

## Architecture

```
AppDelegate
├── HotkeyManager              — CGEvent tap, always alive
├── PanicHotkeyManager         — force-quit shortcut, always alive
├── MenuBarController          — NSStatusItem, profiles submenu, conversations submenu
├── ProfilesStore              — @Observable singleton, profiles.json
├── ConversationStore          — @Observable singleton, conversations/<uuid>.json
├── CommandPanelController     — Replaces OverlayWindowController
│   └── CommandPanelView       — SwiftUI, two-column Raycast-style panel
└── SettingsWindowController   — Raycast-style policy switching
    └── SettingsView           — Profiles tab + existing tabs
```

---

## Data models

### AIProfile (`AIProfile.swift`)
```swift
struct AIProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var provider: Provider      // now Codable (String raw value)
    var model: String
    var systemPrompt: String
    var maxOutputTokens: Int    // output only — matches all provider APIs
    var temperature: Double
    var createdAt: Date
}
```
Storage: `~/.config/blind-spot/profiles.json` (0o600)  
Active profile: UserDefaults key `"activeProfileId"`

### Conversation (`ConversationStore.swift`)
```swift
struct Conversation: Codable, Identifiable {
    var id: UUID
    var title: String
    var messages: [ConversationMessage]
    var profileId: UUID         // locked at creation
    var createdAt: Date
    var updatedAt: Date
}
```
Storage: `~/.config/blind-spot/conversations/<uuid>.json`

### ConversationMessage (`ConversationMessage.swift`)
```swift
struct ConversationMessage: Codable {
    enum Role: String, Codable { case system, user, assistant }
    let role: Role
    let content: String
}
```

---

## Token accounting

ALL providers use `max_tokens` / `maxOutputTokens` to control **output tokens only**. Input tokens are bounded server-side by the model's context window — there is no API parameter to limit them separately. One `maxOutputTokens` field per profile is the correct design. The label in Settings reads "Max Output Tokens".

Provider mapping:
- OpenAI / DeepSeek / Grok / OpenRouter: `"max_tokens"` in request body
- Anthropic: `"max_tokens"` in request body
- Gemini: `"generationConfig.maxOutputTokens"`
- Ollama: `"options.num_predict"` (or `max_tokens` in newer versions)

---

## AIService refactor

New signature:
```swift
static func query(
    _ messages: [ConversationMessage],
    profile: AIProfile
) async throws -> AsyncThrowingStream<String, Error>
```

All `Config.*` reads replaced with `profile.*`. Temperature added to all providers. API keys read via `static func apiKey(for: Provider)` (sync, reads env vars first then key files directly).

---

## File map

| File | Status |
|---|---|
| `AIProfile.swift` | NEW — AIProfile struct + ProfilesStore singleton |
| `ConversationStore.swift` | NEW — Conversation struct + ConversationStore singleton |
| `CommandPanelController.swift` | NEW — replaces OverlayWindowController |
| `CommandPanelView.swift` | NEW — replaces OverlayView, Raycast-style two-column UI |
| `CommandPanelViewModel.swift` | NEW — @Observable VM for panel state |
| `AIService.swift` | UPDATED — accepts AIProfile, adds temperature |
| `Config.swift` | UPDATED — Provider now Codable |
| `SettingsView.swift` | UPDATED — Profiles tab, Raycast policy switching, renamed Settings→Preferences |
| `MenuBarController.swift` | UPDATED — Profiles submenu, Conversations submenu |
| `AppDelegate.swift` | UPDATED — wires ProfilesStore/ConversationStore, uses CommandPanelController |
| `PreferencesStore.swift` | UPDATED — adds closeOnFocusLoss |
| `ConversationMessage.swift` | UPDATED — added Codable |
| `OverlayWindowController.swift` | DELETED |
| `OverlayView.swift` | DELETED |
| `HistoryStore.swift` | DELETED |

---

## Implementation phases

### Phase 1 — Data layer ✅
- `AIProfile.swift` — AIProfile + ProfilesStore (migration from legacy settings)
- `ConversationStore.swift` — Conversation + ConversationStore (migration from HistoryStore)
- `ConversationMessage.swift` — added Codable

### Phase 2 — AIService refactor ✅
- `AIService.swift` — accepts AIProfile, temperature for all providers, static apiKey helper

### Phase 3 — Command panel ✅
- `CommandPanelController.swift`
- `CommandPanelView.swift`
- `CommandPanelViewModel.swift`

### Phase 4 — Settings: Profiles tab + policy switching ✅
- Profiles tab (ProfilesTabView + ProfileEditorView)
- Raycast-style window management in SettingsWindowController
- Renamed "Settings" sidebar tab to "Preferences"

### Phase 5 — Menu bar ✅
- `MenuBarController.swift` — Profiles submenu + Conversations submenu
- Observes conversationsDidUpdate

### Phase 6 — Polish (pending)
- Panel appearance animation (alpha fade 0→1 on show, reverse on hide)
- Streaming cursor (blinking `|` during loading)
- Profile chip in panel bottom bar — tap to quick-switch profile
- Onboarding rework — explain profiles concept, create Default profile in wizard

---

## Key design decisions

| Decision | Outcome |
|---|---|
| Profile per conversation | Conversations lock to the profile active at creation. `profileId` never changes. |
| Hotkey without selection | Panel always opens. Empty input for free-form questions. |
| Panel width | `min(screenWidth * 0.80, 880px)`. Sidebar visible above ~700px total. |
| Click-outside behavior | Default: panel stays open (only ESC closes). Optional setting: close on focus loss. |
| Onboarding | Not re-triggered for existing users. Profiles concept to be added in a future update. |

---

## Storage layout

```
~/.config/blind-spot/
  profiles.json                 — JSON array of AIProfile (0o600)
  conversations/
    <uuid>.json                 — one file per Conversation (max 100)
  keys/
    openai                      — API key files (0o600)
    anthropic
    gemini
    deepseek
    grok
    openrouter
  system-prompt.txt             — legacy global prompt (still read during migration)
```

---

## Build & test

```bash
swift build
pkill BlindSpot; .build/debug/BlindSpot &

# Verify panel
# - Hotkey shows new borderless rounded panel
# - Panel is invisible in screenshot (Cmd+Shift+4)
# - ESC hides panel, focus returns to previous app
# - Sidebar shows conversations after first query
# - Cmd+N starts new conversation
# - Cmd+K focuses sidebar search

# Verify profiles
# - Open Settings → Profiles tab
# - Create a new profile, set model to gpt-4o-mini
# - Set as Active, trigger hotkey — verify gpt-4o-mini is called
# - Switch back to Default profile from menu bar

# Verify Settings window management
# - Open Settings → BlindSpot appears in Dock + Cmd+Tab
# - Close Settings → Dock icon gone, menu bar icon still there
# - Hotkey still works after settings closed

# Verify migration
# - First launch with existing settings creates "Default" profile
# - Old HistoryStore entries appear in sidebar as conversations
```
