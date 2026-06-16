# BlindSpot — To-Do List

All v2.0.0 tasks complete. See git history for details.

## Auto-Answer — Beta Polish
The auto-answer feature (`⌘⌥A` single / `⌘⌥⇧A` answer-all) is functional but in **beta**. Known rough edges to address before stable release:

- **Text inputs (short answer / essay):** Clipboard-based paste works in most browsers but can fail if the page captures Cmd+V events.
- **Multi-select (checkboxes):** AI prompt emphasizes multiple answers but LLMs occasionally return only one letter.
- **Ordering questions:** AX detection of Moodle's sortable-list works, but writing back the correct order depends on matching MD5 hash keys — fragile without server context.
- **Answer-All position isolation:** The lower-bound / upper-bound text collection can miss question text when fields are irregularly spaced.
- **Safe Exam Browser / lockdown browsers:** May block AX access entirely. Not fixable from BlindSpot's side.
- **Select dropdowns:** Keyboard fallback (open menu → type letter → Return) is fragile and depends on menu timing.

## Completed (v2.0.x)

1. Settings Design — Match Panel Aesthetic ✅
2. Provider Tab — Rethink or Remove ✅
3. Copy Button on AI Responses ✅
4. Delete Chats in the Panel ✅
5. Chat Folders / Topics ✅
6. Export Chats or Folders ✅
7. Panel Persistence ✅
8. DMG remove image, leave white BG ✅
9. Fix Prompt Instructions Input ✅
10. Redesign Onboarding to match Panel and settings aesthetics ✅
11. Copy button easy accessible in chat + auto copy last response option in settings ✅
12. Real provider SVG icons in onboarding and throughout ✅
