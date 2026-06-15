# BlindSpot — To-Do List

## 1. Settings Design — Match Panel Aesthetic
The settings window uses `.ultraThickMaterial` and a basic sidebar, but the command panel uses `.ultraThinMaterial`, `RoundedRectangle(cornerRadius: 16)`, and a glass border. Settings should use the same visual language: thinner material, rounded container, consistent typography and spacing.

## 2. Provider Tab — Rethink or Remove
The current Provider tab is redundant now that each AI profile has its own provider + model picker. Options:
- **Option A — Remove it**: Delete the Provider tab entirely. All provider/model config lives in Profiles.
- **Option B — Keep as a quick-switch list**: Replace the current pickers with a clean icon grid (like the onboarding screen) showing all providers, with the active profile's provider highlighted. Useful for users who want a one-click provider swap without opening the Profiles editor.
- **Leaning toward Option A** unless quick-switch without creating a new profile is a common workflow.

## 3. Copy Button on AI Responses
Each AI response turn in the command panel should have a copy button (clipboard icon) that appears on hover. Copies the plain-text response to the clipboard. Placed in the top-right corner of the response bubble.

## 4. Delete Chats in the Panel
Add a delete button to each conversation row in the sidebar (visible on hover, or via right-click context menu). Confirm before deleting. Calls `ConversationStore.shared.delete(id:)`.

## 5. Chat Folders / Topics
Group conversations into named folders (e.g. "Work", "Research"). Data model:
- Add `folderId: UUID?` to `Conversation`
- New `Folder` struct + `FolderStore` (similar pattern to `ProfilesStore`)
- Sidebar shows folders as collapsible sections above the date groups
- Drag-and-drop or right-click → "Move to folder" to assign

## 6. Export Chats or Folders
Export a single conversation or a whole folder as:
- **Markdown** (`.md`) — clean, readable, shareable
- **JSON** — full fidelity, re-importable
- Triggered via right-click context menu in the sidebar or a toolbar button
- Uses `NSSavePanel` to let the user choose the destination
