# Sketch: Calendar-driven personal scheduler (`sched`)

**Date**: 2026-11-20
**Status**: exploring

## Motivation

The user wants a "cron for anything". It must cover one-off and recurring jobs, show them in Calendar.app, and run a Hammerspoon action or a bash script when a job is due. A job can also message a live Claude Code session, as an optional handler. The user does not know how to keep a schedule like this up to date.

Most of the parts already exist. `lib/lua/seeds/calendar/` polls EventKit each minute and fires Lua actions for tagged events. The repo also has a launchd service pattern (`services/*/`, `bin/service-wrapper`), notifications through `terminal-notifier` (`services/server-check/script.sh:17`), Hammerspoon URL handlers (`seeds/copylink.lua`, `seeds/rolevote.lua`), a live-session finder (`bin/cc-peers`) and a Lua test harness (`tests/lib/lua/harness.lua`). The current seed is built for heads-up notifications, though, not for running jobs. Reading the code shows four defects that would make it run jobs wrongly.

### Critique of the current proposal

**Bugs I checked against the code. The main session's description is corrected where it was wrong.**

1. **Recurring events fire every third day, not every other day.** `calendar_query.py:100` emits `calendarItemIdentifier()`, and all occurrences of a recurring event share it. `getTriggerKey` (`init.lua:463`) has no time in the key. A record is written at trigger time and removed only when its age is strictly over 48 h (`init.lua:489–494`). Cleanup runs on only 1 poll in 100, and it runs *after* `processEvents` (`init.lua:643–648`). Take a daily event that fires at T:
   - At T+24h the record blocks the event.
   - At T+48h±2min the record is about 48 h old, and cleanup has almost certainly not run in that minute, so it blocks again.
   - At T+72h the event fires. The chance that no cleanup ran in the 1,440 polls between T+48h and T+72h is about 0.99^1440 ≈ 5×10⁻⁷.
   
   So a daily event runs every third day. An hourly event fires once and then stays blocked for about 49–50 h. Weekly events are not affected (168 h > 48 h). The existing `focus` and `notify` tags have the same bug today.
2. **Missed runs can never be caught up, even with a "late" rule.** The query starts at now (`calendar_query.py:87`), and `shouldTrigger` rejects `secondsUntil < 0` (`init.lua:519`). A short event that ended while the Mac slept is never returned. A long event that is still running is returned, but it is rejected. Catching up needs a lookback query and a record of the last poll time.
3. **No calendar filter, and the filter that exists matches by title.** The seed passes no calendar names, so every calendar is queried, including invitations and subscriptions. When names are given, the filter is `c.title() in calendars` (`calendar_query.py:82`). Titles are not unique, so a subscribed or shared calendar that someone names "Automations" would pass.
4. **The proposed tag cannot match.** `tagPattern = "#%{anthony/autocal:([%w-_]+)%}"` (`hammerspoon.lua`, calendar config) has no `:` in its class, so `#{anthony/autocal:run:foo}` captures nothing. Also, `%w-_` inside a Lua set uses a class as a range endpoint, which is undefined. Write `[%w_-]` instead.
5. **The timing model is wrong for jobs.** The window is `leadMinutes ± pollInterval`, which is a heads-up model. A job is "due when start ≤ now and the job is not in the state file". That is a different code path, not a new tag in the old one.
6. **Time handling is weak around DST.** Python sends naive local strings (`nsdate_to_local_string`), and Lua parses them back with `os.time` (`init.lua:442`). In the fall-back hour, "01:30" is ambiguous, so one of the two instants is wrong by an hour. Fix: send epoch seconds from `timeIntervalSince1970()` and never parse strings.
7. **No wake trigger.** The only `hs.caffeinate.watcher` in the repo is commented out with a FIXME (`lib/lua/lib/wakeDialog.lua:47`). After a wake, the next poll waits for the `doEvery` timer.

**Missing from the proposal:**

- **Occurrence identity.** Per Apple's documentation (not tested here), `eventIdentifier` and `calendarItemIdentifier` are the same for every occurrence. `occurrenceDate` tells occurrences apart, and it keeps the *original* date when one occurrence is moved (detached). `calendarItemIdentifier` can change after a full sync, and `eventIdentifier` is documented as more stable. So the key should be `eventIdentifier + occurrenceDate + handler`. Two results follow:
  - A detached occurrence that already ran, and is then moved later, does not run again. This is good.
  - For a non-recurring event, `occurrenceDate` probably follows `startDate`. Editing the time of a one-off job that already ran would then run it again. This is acceptable, but it needs a note in the docs and a check in the probe.
- **Recurrence expansion.** `predicateForEventsWithStartDate:endDate:calendars:` expands recurring events into separate occurrences. It accepts ranges in the past, is capped at 4 years, and returns any event that *overlaps* the range, not only events that start inside it. Overlap is harmless here because the key removes duplicates. These facts come from the documentation and must be confirmed by the probe in step 0.
- **Invitations and shared calendars.** An accepted invitation can land in any calendar. If the Automations calendar is on iCloud, anyone with write access to it, or to the iCloud account, can schedule handler runs. EventKit does not show who a calendar is shared with. Defenses:
  - Allow one calendar, chosen by `calendarIdentifier`.
  - Refuse that calendar if `isSubscribed()` is true or `allowsContentModifications()` is false.
  - Skip events that have attendees or an organizer who is not the user.
  - Make handlers treat all event text as untrusted data. The allowlist limits *which* code runs, but the attacker still controls the arguments.
- **Prompt injection through the `claude` handler.** Calendar text sent to a live Claude session that has Bash is a write path into an agent. The handler must send a template stored in the repo, chosen by name. It must never pass raw notes as the message (see step 9).
- **Two Macs.** If the calendar syncs and a second Mac runs the same dotfiles and Hammerspoon, both Macs run every job. Gate the runner on a configured `runnerHost`.
- **iCloud delay.** An event made on the phone a minute before it is due can arrive late. The late rule covers delays up to 2 h. `sched add` writes on this Mac, so it has no delay.
- **Concurrency and hung handlers.** `hs.task` is async. A handler needs a timeout, and the runner must skip a job if the same key is already running. It writes the "running" state before it starts the handler, so each occurrence runs at most once.
- **Visibility.** Today the only history is `hs.settings` and the Hammerspoon console. The design needs a run log that the terminal can read, plus one notification for each failure or missed job.
- **All-day events** start at local midnight. Refuse them in the Automations calendar with a warning, rather than guess an hour.

**More than the job needs:**

- The `.ics` feed (see Q1).
- A cron-expression parser. Calendar.app's repeat options are the parser.
- `sched add` with full repeat-rule parsing in the first slice. The user can make events in Calendar.app from the start.
- Title triggers and a countdown for jobs. These features exist for heads-up alerts. Jobs do not need them.

## Design

### Recommendations on the open questions

**Q1, where the schedule lives: Calendar.app events, with a limit on frequency.**
- A subscribed `.ics` feed is **read-only in Calendar.app**, so the user could see jobs but not add, move or delete them there. Every change would need an edit in the repo, a regenerated feed and a launchd reload. That gives two sources to keep in step, which is exactly the "keep it up to date" problem.
- With Calendar.app as the source, the answer to "how do I keep it up to date" is that nothing needs updating. The runner reads the calendar on every poll. The repo holds only handler code. The only drift is an event that names a handler that does not exist, and `sched check` plus a warning at poll time catch that.
- Limit: jobs that run more often than hourly do not go in the calendar. They clutter it, and each one expands into many occurrences in every query. They stay as launchd services (`service create`, `StartCalendarInterval`), the existing pattern.

**Q3, the runner: the Hammerspoon seed, as a separate job path inside it.**
- Hammerspoon already holds the Calendar permission. `calendar_query.py` runs as an `hs.task` child, so macOS treats Hammerspoon as the responsible app, and it works today. A launchd agent that runs python would make the pyenv python binary the app that asks for permission. That path changes when python is upgraded, and a background agent cannot reliably show the permission prompt. `docs/live-transcribe.md:4` shows what a stable grant costs: a self-signed app bundle that is rebuilt with the same certificate.
- The user's late rule (run if under 2 h late) already covers the seconds-long gap of a Hammerspoon reload. A Hammerspoon crash leaves a longer gap. `last_poll` in the state file, with a warning from `sched status`, makes that gap visible.
- "Run a Hammerspoon action" is a stated need. In-process Lua handlers meet it directly.
- Upgrade path: if Hammerspoon proves unreliable, move the runner to a signed Swift CLI under launchd. It would use the same state file, handler contract and query script, so the change is a swap.

### Components and file layout

```
lib/lua/seeds/calendar/calendar_query.py   # extended: epoch range, epoch times, ids
lib/lua/seeds/calendar/init.lua            # existing tag path (key bug fixed) + calls sched
lib/lua/seeds/calendar/sched.lua           # new: job path (due / late / missed), runner
lib/lua/seeds/calendar/sched_due.lua       # new: pure function, unit-tested under lua5.4
sched/handlers/<name>                      # allowlisted executables, tracked (public repo)
sched/templates/claude/<name>.txt          # fixed messages for the claude handler
bin/sched                                  # CLI (python, PyObjC, same interpreter as the query)
~/.local/state/sched/state.json            # per-occurrence records + last_poll
~/.local/state/sched/runs.jsonl            # append-only run log
~/.log/sched/<handler>.log                 # handler stdout/stderr, timestamped
tests/lib/lua/test_sched_due.py            # drives sched_due.lua via the existing harness
```

### Steps

0. **Read-only EventKit probe** (`.cc/scripts/sched-ek-probe.py`, run from iTerm, writes nothing). For every calendar it prints `title`, `calendarIdentifier`, source type, `isSubscribed`, `allowsContentModifications`. For a recurring test event over a past and future range it prints `eventIdentifier`, `calendarItemIdentifier`, `occurrenceDate`, `startDate`, `isDetached` and `hasAttendees`. It confirms three things: occurrences share ids, `occurrenceDate` stays the same after a move, and the predicate returns past occurrences. It also shows whether an "On My Mac" calendar can exist next to iCloud. The user makes the test event by hand.

1. **Extend `calendar_query.py`** without breaking the current call.
   - Add an optional `--from EPOCH --to EPOCH`, and keep the positional `hours` argument.
   - Add these fields to each event: `start_epoch`, `end_epoch`, `occurrence_epoch` (from `occurrenceDate`), `event_id` (`eventIdentifier`), `calendar_id`, `is_detached`, `has_attendees`.
   - Keep the old string fields for the existing path.
   - Run one query per poll over `[query_from, now + queryWindow]`, for all calendars. Filter in Lua, so the existing tags keep working.

2. **Fix the existing trigger key** in `init.lua`: `getTriggerKey(event_id .. "@" .. occurrence_epoch, …)`. Make cleanup deterministic, once per poll, after a fixed 8 days. That covers the lookback limit in step 5. This also fixes the `focus` and `notify` tags.

3. **Config** in `lib/lua/hammerspoon.lua`, in the calendar `engage` call:
   ```lua
   sched = {
     calendarId = "<calendarIdentifier from probe>",
     runnerHost = "minimac",           -- hs.host.localizedName() must match
     graceSeconds = 2 * 3600,          -- user decision: late-run window
     lookbackCap = 7 * 24 * 3600,
     timeoutSeconds = 600,
     luaHandlers = { ["focus-mode"] = function(job) ... end },
   }
   ```

4. **Tag and handler contract.**
   - The tag goes in the title or notes: `#{anthony/autocal:run:<handler>}`. It is matched by its own pattern, `#%{anthony/autocal:run:([%w_-]+)%}`, and `<handler>` must match `^[a-z0-9][a-z0-9_-]*$`.
   - An event fires only if all of these hold: it is in `calendarId`, the calendar is not subscribed and is writable, the event is not all-day, it has no attendees, and `hs.host.localizedName() == runnerHost`.
   - Lookup order: first `luaHandlers[name]`, then the executable `sched/handlers/<name>`. If neither exists, record `unknown-handler` and send one notification.
   - A script handler is started with `hs.task.new(path, cb, {})`: no shell, no arguments, and cwd set to the handlers folder. The event JSON goes in on stdin with these fields: `key, handler, title, notes, start_epoch, occurrence_epoch, late_seconds, calendar_id`. The environment carries `SCHED_KEY` and `SCHED_LATE_SECONDS`.
   - Exit 0 means `ok`. Any other exit means `failed`. A timeout means `killed`.
   - Handlers must treat `title` and `notes` as untrusted. A bash handler that needs a Hammerspoon action calls `open -g "hammerspoon://…"`, the copylink/rolevote pattern.

5. **Due, late and missed logic** (`sched_due.lua`, pure, with no `hs.*` calls).
   - Inputs: `now`, `last_poll`, `occurrences`, `state`, `grace`.
   - Query range start: `query_from = max(now - lookbackCap, min(last_poll, now - grace))`. On the first ever run, `last_poll = now`, so nothing older is filled in.
   - For each tagged occurrence whose `start_epoch <= now` and whose key is not in `state`:
     - If `now - start <= grace`, run it. Status is `ok`, or `late` if the delay is over 120 s.
     - Otherwise, record `missed`.
   - After a long sleep, all missed jobs go into **one** notification: "N jobs missed while asleep", listing their titles.
   - Write `last_poll = now` only after a successful query. A failed query must not move the lookback forward.
   - Event edited or deleted before it is due: it is not returned, so it does not run. Edited after it ran: the key holds, so it does not run again, except for the one-off edge in "Occurrence identity".

6. **Runner** (`sched.lua`).
   - Write a `running` record to `state.json` (atomic write: temp file, then rename) before the handler starts.
   - On finish, update the record and append a line to `runs.jsonl` with `{key, handler, title, start_epoch, ran_at, late_seconds, status, exit, duration_ms}`.
   - Tee handler output to `~/.log/sched/<handler>.log` with a timestamp.
   - On `failed`, `killed` or `unknown-handler`, send one notification with `hs.notify`. A click opens the log.
   - Skip a key that is already running.
   - Add an `hs.caffeinate.watcher` for `systemDidWake` that calls `heartbeat()` after a 20 s delay, so the network and iCloud can settle first.
   - Each run of this watcher's `start()` must stop the earlier watcher. Otherwise every soft reload adds a duplicate, the same hazard CLAUDE.md warns about.

7. **`bin/sched`, read-only in the first slice.**
   - `sched status`: shows `last_poll` age, with a warning over 5 min. It also shows the next 5 jobs and the last 5 runs.
   - `sched log [-n N] [--failed]`: reads `runs.jsonl`, with times in local time.
   - `sched check`: lists upcoming Automations events and marks unknown handlers, all-day events, events with attendees, and a wrong calendar id.
   - `sched calendars`: prints the ids, for the config in step 3.
   
   Run from iTerm or from a Claude Bash call, iTerm is the responsible app, the same as `bin/agenda`.

8. **Slice 2: `sched add`.**
   - Syntax: `sched add "<title>" --handler NAME --at "2026-11-21 09:00" [--every day|weekday|week] [--until DATE] [--note TEXT]`.
   - It builds one `EKEvent` with an `EKRecurrenceRule`, saves it to `calendarId` with `saveEvent:span:commit:error:`, and prints the new `eventIdentifier`.
   - `sched rm <event_id>` removes it, after a confirmation prompt. No other repeat syntax is supported. Anything more complex is made in Calendar.app.

9. **Slice 2: the `claude` handler** (`sched/handlers/claude`).
   - Notes carry `claude: <template-name>` and an optional `to: <session name>`. The handler reads `sched/templates/claude/<template-name>.txt` and sends that file's text only, with the event title as one quoted label line. Raw notes are never sent.
   - It finds a live target through `alt` (syntax not yet known, see Open Questions). Otherwise it uses `bin/cc-peers`-style liveness, a pid plus its start time from `~/.claude/sessions/*.json`, matched on `name`.
   - If no session is live, it sends a notification with the message text and exits 0, with status `ok` plus `"delivered":"notification"`.

**First shippable slice:** steps 0–7. That means the probe, the query fields, the key fix, the job path with the late and missed rule, script and Lua handlers, the state file and run log, the wake trigger, `sched status|log|check|calendars`, one example handler (`sched/handlers/notify-test`) and the `sched_due.lua` tests. The user makes jobs in Calendar.app. `sched add` and the `claude` handler come in slice 2.

**Tests:** register nothing new. `lib/lua` is already a component (`docs/testing.md`). Run the tests with `cmds test lua`. Cases to cover:
- A daily occurrence on consecutive days runs every day.
- A detached, moved occurrence does not run again.
- A job 30 min late runs with status `late`.
- A job 3 h late is recorded as `missed`.
- A wake after 2 days runs only the jobs inside the 2 h grace and summarises the rest.
- The first ever poll fills in nothing.
- A failed query does not move `last_poll`.
- A DST fall-back instant at 01:30 is handled by epoch time only.

## Open Questions

- **Where the Automations calendar lives.** An "On My Mac" calendar never syncs, cannot be shared and has no iCloud delay, but it does not show on the phone. When iCloud calendars are on, macOS may also hide or refuse local calendars. The probe in step 0 settles this. If iCloud is the only option, the risk is accepted: an attacker in the iCloud account can call allowlisted handlers with crafted text, and step 4's untrusted-input rule is the defense.
- **Should a one-off job run again after its time is edited?** This depends on how `occurrenceDate` behaves for non-recurring events, which the probe checks. The current proposal says yes, with a note in the docs.
- **The `alt` command was not run**, because it needs approval. The only evidence for it is the allowlist entry `Bash(alt message send:*)` in `rcs/claude-settings.json:33`. Still unknown: the agent-id format, how to find the liaison's id, whether `alt` can report liveness, and whether messages to a dead agent queue or fail. These decide whether the handler uses `alt` or falls back to `cc-peers`.
- **Can Hammerspoon timers fire during a dark wake (Power Nap), and should jobs run then?** Suggestion: run them anyway, because the user's late rule allows late runs. This is not verified.
- **Do private handlers need a second folder** (for example in `~/Vaults/work-config`), because `sched/handlers/` is in a public repo? A tracked handler that calls a private script may be enough.
- **The `notify-test` example handler** needs a clear name, so that the probe and the first live test cannot be taken for a real job.

## Related

- `lib/lua/seeds/calendar/init.lua`, `calendar_query.py`. Bugs at lines 87, 100 (py) and 442, 463, 489, 519, 643 (lua)
- `lib/lua/hammerspoon.lua`: calendar `engage` config and `tagPattern`
- `docs/hammerspoon.md` "Calendar Seed" (about line 203). It already documents the no-catch-up gap and needs a "Jobs" section
- `lib/lua/lib/wakeDialog.lua:47`: the commented-out wake watcher
- `lib/lua/seeds/copylink.lua`, `rolevote.lua`: the `hs.urlevent` pattern for bash → Hammerspoon actions
- `bin/cc-peers`: session liveness from `~/.claude/sessions/<pid>.json`
- `services/server-check/`: notification pattern (`terminal-notifier`), launchd layout, `bin/service-wrapper`
- `bin/agenda`, `sanctuary/calendar.swift`: Swift EventKit reader (iTerm is the responsible app)
- `misc/check_calendar_auth.py`: an existing permission-status probe to reuse in step 0
- `docs/live-transcribe.md:4`: what a stable permission grant for a background binary costs (signed bundle)
- `tests/lib/lua/harness.lua`, `docs/testing.md`: where `sched_due.lua` tests run
- `.cc/misc/scheduler/recon-brief.md`: the brief for this sketch
