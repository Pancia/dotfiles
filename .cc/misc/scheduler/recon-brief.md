Critique, investigate and sketch a personal scheduler for one-off and recurring jobs on this Mac (dotfiles repo, ~/dotfiles).

## What the user wants
- Schedule one-off and recurring "misc" jobs, like cron but for anything.
- Jobs should show in macOS Calendar.app, ideally.
- A job triggers the user's code: a Hammerspoon action or a plain bash script.
- If a Claude Code session is live (e.g. the dotfiles Altera liaison), a job may message it. This is a handler/callback, not a core feature.
- The user is unsure how to "keep it up to date".

## Current proposal (from the main session — critique it, do not just confirm it)
- Calendar.app is the source of truth. A dedicated "Automations" calendar; only events in it may run code.
- Extend the existing Hammerspoon calendar seed: lib/lua/seeds/calendar/init.lua (660 lines) and calendar_query.py (EventKit via PyObjC). Config is in lib/lua/hammerspoon.lua around line 52. Docs: docs/hammerspoon.md "Calendar Seed" (~line 203).
- Tag form `#{anthony/autocal:run:<handler>}` maps to an allowlisted script in a handlers directory, called with event JSON. No raw commands in event text.
- A `claude` handler uses `alt message send <agent-id> <text>`; falls back to a macOS notification when no session is live.
- A `sched add` CLI creates events through EventKit (so Claude or the user can schedule from the terminal). bin/agenda and sanctuary/calendar.swift already read events with Swift.

## Decided by the user
- Q2 missed runs: "late" — on wake, run a missed job if it is under ~2 hours late; older misses get a "missed" notification.

## Still open (give a recommendation with reasons)
- Q1 source of truth: Calendar.app events vs launchd jobs + a published .ics feed.
- Q3 runner: the Hammerspoon seed (has Calendar TCC grant; stops during reload/crash) vs a new launchd service polling each minute (needs its own Calendar grant). See services/ and bin/service for the launchd pattern.

## Known bugs found by reading code (verify)
- Recurring events: calendar_query.py emits event.calendarItemIdentifier(), shared by all occurrences. getTriggerKey in init.lua has no start time, and records expire after 48h, so a daily event fires about every other day.
- No catch-up: the trigger window is leadMinutes ± pollInterval; a sleeping Mac skips it silently.
- The query covers all calendars (calendars=None), so an invite carrying the tag would fire.

## What to produce
1. Critique: what breaks, what is over-built, what is missing (sleep/wake, DST, time zones, event edits/deletes, iCloud sync delay, TCC for background processes, concurrency, logging, how to see what ran and what failed, security of a calendar that can run code incl. shared/iCloud calendars).
2. Investigate the open questions with evidence from the repo (and EventKit facts: occurrence identity, occurrenceDate, recurrence expansion in predicates).
3. Sketch the smallest design that works: components, file layout, tag/handler contract, state file, missed-run logic, the Claude-messaging handler, and the `sched` CLI surface. Say what the first shippable slice is.
4. Note any existing dotfiles tool that already covers part of this, so we reuse it.

Do not edit any file outside your sketch artifact. Do not create Calendar events or calendars.
