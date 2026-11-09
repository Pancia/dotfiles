# Sanctuary Claude Integration Plan

## Summary

Integrate Claude Code into the sanctuary workflow to provide:
1. Dynamic, mood-aware journal templates (instead of static 3-question template)
2. Claude chat at session start (intention setting) and end (review)
3. Display vision + areas/projects for selection
4. Quick-capture prompts at pymodoro work_end hooks
5. Session state persistence between start and review

---

## Files to Create (test separately, don't modify existing scripts)

| File | Purpose |
|------|---------|
| `sanctuary/main-claude.fish` | **New standalone script** with Claude integration (test before replacing main.fish) |
| `sanctuary/review.fish` | End-of-session review flow with Claude |
| `sanctuary/prompts/session-start.md` | Claude system prompt for intention setting |
| `sanctuary/prompts/journal-template.md` | Claude prompt for dynamic template generation |
| `sanctuary/prompts/session-review.md` | Claude system prompt for end-of-session review |
| `fish/functions/sanctuary-build-context.fish` | Aggregates context from TheAkashicRecords |
| `fish/functions/sanctuary-list-focuses.fish` | Lists areas/projects for fzf selection |

## Files to Modify (later, after testing)

| File | Change |
|------|--------|
| `rcs/pymodoro-config.yaml` | Add hooks for quick-capture and session-end review |
| `lib/lua/core.lua` | Extend `pomodoroNotify()` with quick-capture action |
| `sanctuary/main.fish` | Replace with main-claude.fish once tested |

## Directories to Create

- `~/.local/state/sanctuary/` - Session state persistence
- `sanctuary/prompts/` - Claude system prompts

---

## Implementation Phases

### Phase 1: Context Building Functions

Create helper functions to aggregate context for Claude:

**`fish/functions/sanctuary-build-context.fish`**
- Reads and concatenates: vision.md, anchors.md, NOW.md
- Lists areas/*.md and projects/*.md with descriptions
- Fetches calendar (next 8 hours)

**`fish/functions/sanctuary-list-focuses.fish`**
- Outputs `path|display_name|description` for fzf
- Scans areas/ and projects/ directories

### Phase 2: Claude System Prompts

**`sanctuary/prompts/session-start.md`**
- Warm but focused tone
- Acknowledge mood with compassion
- Help set clear, achievable intention
- Connect work to deeper purpose (vision)

**`sanctuary/prompts/journal-template.md`**
- Generate 3-5 reflective questions based on mood/focus
- Include body-awareness question
- Include gratitude angle
- Output markdown with `<INSERT>` marker

**`sanctuary/prompts/session-review.md`**
- Celebrate accomplishments
- Identify key learning
- Suggest what to carry forward
- Transition out of work mode gracefully

### Phase 3: New main-claude.fish Script

```
1. Display vision.md
2. Display calendar (8hrs)
3. Prompt for mood ("How are you feeling?")
4. fzf selection of area/project (with preview)
5. Claude intention-setting (--print mode)
6. User confirms/refines intention
7. Claude generates dynamic journal template
8. Create session state file (JSON)
9. Create journal entry with template
10. Open Neovim at <INSERT>
11. Return to interactive shell
```

**Session state file:** `~/.local/state/sanctuary/current-session.json`
```json
{
  "session_id": "2025-12-15T09:30:00",
  "focus": "projects/conscious-computing",
  "mood": "focused but tired",
  "intention": "Implement sanctuary Claude integration",
  "work_sessions_completed": 0,
  "started_at": "2025-12-15T09:30:00"
}
```

### Phase 4: Pymodoro Hooks

**Add to `rcs/pymodoro-config.yaml`:**

```yaml
work_end:
  # ... existing hooks ...
  - command: "fish -c 'sanctuary-work-end-hook'"
    blocking: false

app_stop:
  # ... existing hooks ...
  - command: "fish -c 'sanctuary-session-end-hook'"
    blocking: false
```

**`sanctuary-work-end-hook`** (fish function):
- Calls `hs -c 'sanctuaryWorkEndPrompt()'`
- Hammerspoon shows quick text dialog
- User can capture what they accomplished
- Appends to journal

**`sanctuary-session-end-hook`** (fish function):
- Launches `sanctuary/review.fish` in new Kitty tab
- Only if session state file exists

### Phase 5: Extend pomodoroNotify for Quick-Capture

**Modify existing `pomodoroNotify()` in `lib/lua/core.lua`:**

- Add "Quick Note" action button to the work_end notification
- Clicking opens a text input dialog
- User can capture what they accomplished
- Appends to `~/TheAkashicRecords/_main.md`

This extends the existing notification UX rather than creating a separate popup.

### Phase 6: Review Flow

**`sanctuary/review.fish`:**
1. Read session state (focus, intention, mood, sessions completed)
2. Display session summary
3. Interactive Claude session for reflection
4. Prompt for key takeaway
5. Append takeaway to journal
6. Clean up session state file
7. **Lock screen** via `pmset displaysleepnow` or `hs -c 'hs.caffeinate.lockScreen()'`

---

## Key Design Decisions

1. **fzf for area/project selection** - Consistent with existing patterns, faster than Claude conversation
2. **`claude --print` for templates** - Non-blocking, fast generation
3. **Interactive Claude for review** - Richer dialogue for reflection
4. **JSON session state** - Simple persistence, easy to read from Fish/Lua
5. **Hooks via pymodoro config** - Uses existing infrastructure

---

## Context Files (Read-Only)

These files are consumed by Claude but not modified by this implementation:

- `~/TheAkashicRecords/vision.md` - Purpose & goals
- `~/TheAkashicRecords/anchors.md` - Daily check-ins, vow, rituals
- `~/TheAkashicRecords/NOW.md` - Current tasks
- `~/TheAkashicRecords/areas/*.md` - Area descriptions
- `~/TheAkashicRecords/projects/*.md` - Project descriptions

---

## Decisions Made

- **Screen lock:** Yes, lock screen when review closes
- **Quick capture:** Extend existing pomodoroNotify notification with action button
- **Split panes:** Keep VPC as-is, iterate on dynamic layouts later
- **Testing approach:** Create new files (main-claude.fish) to test separately before replacing existing scripts
