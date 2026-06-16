# BlindSpot — To-Do List

## 1. Settings Design — Match Panel Aesthetic (Done)
The settings window uses `.ultraThickMaterial` and a basic sidebar, but the command panel uses `.ultraThinMaterial`, `RoundedRectangle(cornerRadius: 16)`, and a glass border. Settings should use the same visual language: thinner material, rounded container, consistent typography and spacing.

## 2. Provider Tab — Rethink or Remove (Done)
The current Provider tab is redundant now that each AI profile has its own provider + model picker. Options:
- **Option A — Remove it**: Delete the Provider tab entirely. All provider/model config lives in Profiles.
- **Option B — Keep as a quick-switch list**: Replace the current pickers with a clean icon grid (like the onboarding screen) showing all providers, with the active profile's provider highlighted. Useful for users who want a one-click provider swap without opening the Profiles editor.
- **Leaning toward Option A** unless quick-switch without creating a new profile is a common workflow.

## 3. Copy Button on AI Responses (Done)
Each AI response turn in the command panel should have a copy button (clipboard icon) that appears on hover. Copies the plain-text response to the clipboard. Placed in the top-right corner of the response bubble.

## 4. Delete Chats in the Panel (Done)
Add a delete button to each conversation row in the sidebar (visible on hover, or via right-click context menu). Confirm before deleting. Calls `ConversationStore.shared.delete(id:)`.

## 5. Chat Folders / Topics (Done)
Group conversations into named folders (e.g. "Work", "Research"). Data model:
- Add `folderId: UUID?` to `Conversation`
- New `Folder` struct + `FolderStore` (similar pattern to `ProfilesStore`)
- Sidebar shows folders as collapsible sections above the date groups
- Drag-and-drop or right-click → "Move to folder" to assign

## 6. Export Chats or Folders (Done)
Export a single conversation or a whole folder as:
- **Markdown** (`.md`) — clean, readable, shareable
- **JSON** — full fidelity, re-importable
- Triggered via right-click context menu in the sidebar or a toolbar button
- Uses `NSSavePanel` to let the user choose the destination

## 7. Panel Persistence (Done)
Before when you opened the panel and clicked outside of it, the panel would persist its state (e.g. open) but now the new panel is like raycast, when you click outside of it, the panel closes. The setting in settings doesn't change anything about this behavior.

- look why it closes when you click outside of it
- make the setting in settings work

## 8. DMG remove image, leave white BG (Done)
Leave the image background white in the DMG, not the generated one from us.

## 9. Fix Prompt Instructions Input (Done)
The text is invisible when typing in there. Look with mcp server and perplexity how to do it in swift.

## 10. Redesign Onboarding to match Panel and settings aesthetics (Done)
Look at the panel and settings aesthetics and make the onboarding flow match them. For example, buttons, text input fields, window size, colors, and fonts.

## 11. Copy button easy accessible in chat not only on hover and auto copy last output option in settings (Done)