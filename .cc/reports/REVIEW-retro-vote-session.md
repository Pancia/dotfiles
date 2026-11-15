# Review: retro suggestions from the vote-links session

Date: 2026-11-15. Scope: `lib/lua/seeds/copylink.lua`, `lib/lua/seeds/rolevote.lua`,
`lib/lua/hammerspoon.lua`, `roleplay/bin/roleplay-roll` and its tests, `rcs/claude-user-claude.md`,
`rcs/claude-settings.json`, `CLAUDE.md`. No project file was changed. The probes ran in a
throwaway folder, with user settings left out (`--setting-sources=local`), so the real
`roleplay-roll` hook never ran.

## Summary

| # | Suggestion | Verdict |
|---|---|---|
| 1 | Document copy links in the user CLAUDE.md | **changed**: shorter text, a fuller encoding rule, and always show the text too |
| 2 | Make vote ids opt-in with `ROLEPLAY_VOTES=1` in settings `env` | **changed**: put the opt-in on the hook command line, not in `env` |
| 3 | Document that hand runs write the real roll log | **changed**: the #2 flag fixes it in code. Add one line of docs |
| 4 | Document live-loading a seed with `hs -c` and `timeout` | **changed**: the hang comes from stdin, so use `</dev/null`. Also fix the soft-reload list, a worse defect |
| 5 | Add a rule to state a per-reply token cost | **changed**: sharper trigger, real numbers, its own short section |
| 6 | Read `XDG_STATE_HOME` in rolevote.lua | **rejected**: Hammerspoon does not have the variable, so the change does nothing |
| 7 | Lua tests for rolevote under lua5.4 | **changed**: use pytest to drive `lua5.4`, not busted. Low priority |

**Collision note for every fix.** The other live session has uncommitted hunks in
`roleplay/docs/claude-roleplay.md`, `roleplay/examples.md` and `roleplay/roster.tsv`. There are
also hunks this session did not make in `rcs/claude-user-claude.md` (the subagent paragraph
under "Where to put work files"), in `rcs/claude-settings.json` (model, advisor and notification
keys), and in `CLAUDE.md` (the cmus and fish-tests rows). So #1, #3, #4 and #5 can collide too,
not only #2. Rules:
- Make every change with the Edit tool, never with Bash, so `ccjj` records it.
- Keep each change in its own hunk, away from those hunks.
- Commit with `/cc:commit`, which routes to `commit-mine` and splits shared files by hunk.
  Never use a raw `jj commit`.
- Never touch `roster.tsv` or `examples.md`.
- `roleplay/README.md`, `roleplay/bin/roleplay-roll` and `roleplay/tests/` have no foreign
  hunks. The env table in `claude-roleplay.md` (about line 240) is far from the other session's
  hunk (line 96).

---

## 1. Copy links are undocumented: changed

**Diagnosis: true.** In the repo and in `~/.claude`, `hammerspoon://copy` appears only in
`copylink.lua`, in this session's file-history copies and in transcripts. `rcs/claude-user-claude.md`
has no mention of it.

**Encoding, from Hammerspoon's own code.** `strings` on `liburlevent.dylib` shows
`componentsSeparatedByString:` and `stringByRemovingPercentEncoding`. The main binary also
names `queryItems`. So the query is probably split by hand on `&` and `=`, and then decoded.
Neither method turns `+` into a space, so a `+` probably stays a literal `+`. I could not open
a URL to confirm this (UNCHECKED). The link
also sits inside Markdown `( )`. So encode every character except letters and digits:
spaces, `)`, `&`, `#`, `%`, `=` and `+` included. `urllib.parse.quote(s, safe='')` does
exactly that. Do not use `quote_plus`.

**Safety.** A Markdown link hides its payload behind its label. Any app or web page can also
call `hammerspoon://copy` and set the clipboard. The clipboard seed shows each new copy, but
only after the copy. So the rule should say: also show the exact text in a code block, next
to the link.

**Placement.** Put it in "Reporting Back", at the end of "Reply format". That section sets how a
reply looks, and a copy link is part of how a reply shows text. (The paragraph in "Questions to
me" about commands is about a command Claude asks to run, not one the user pastes.) Proposed
text, about 50 words:

> **Copy links.** When I must paste text somewhere myself, such as a command for another
> terminal, show it in a code block and add `[copy](hammerspoon://copy?text=…)` after it.
> Percent-encode every character except letters and digits (`urllib.parse.quote(s, safe='')`).
> A space is `%20`, never `+`. A line break is `%0A`.

**Check by hand once:** a link with `&`, `+`, `=` and `)` in the payload copies exactly.

## 2. Vote ids are not opt-in: changed

**Diagnosis: true, and somewhat worse.** The vote receiver, `lib/lua/seeds/rolevote.lua`, is
outside `roleplay/`. So a stranger gets `|| vote id: xxxx` in every tag, with nothing that
reads it. The shared snippet `roleplay/snippets/CLAUDE.md.section` does not explain it, so
their Claude sees unexplained text. They also get a `rolls.tsv` that grows by one line per
prompt, with no rotation. Neither `roleplay/README.md` nor `docs/claude-roleplay.md` mentions
`ROLEPLAY_ROLL_LOG`, vote ids or the log.

**Key question: do hooks inherit the settings `env` block? Yes, tested.** I ran one isolated
`claude -p` with `--setting-sources=local` and a `--settings` file. That file set
`env: {RETRO_ENV_PROBE: "from-settings-env"}` and a `UserPromptSubmit` hook that dumps its
environment. The hook saw `RETRO_ENV_PROBE=from-settings-env`.

**Why `env` is still the wrong place.** The same values reach every Bash-tool child. This
session's Bash environment has `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` and the other `env` keys.
So with `ROLEPLAY_VOTES=1` in `env`, every hand run of `roleplay-roll` from Claude's Bash
would still log. That is exactly problem #3.

**Revised fix: put the opt-in on the hook command line.** A second probe used the hook
command `RETRO_CMDLINE=1 …/hook2.sh --votes`. The hook received `args=--votes` and
`RETRO_CMDLINE=1`. So both an argument and an env prefix work, and only the hook sees them.
Prefer the argument:
- `rcs/claude-settings.json`: `"command": "roleplay-roll --votes"`.
- `roleplay-roll`: add a `--votes` case that sets `mode=hook` and `votes=1`. Write the log and
  add the id only when `votes=1`. Today any unknown argument falls through to hook mode. So an
  old script reading a new settings file still works, and a new script without the flag fails
  open to a plain roll.
- Tests: the `run()` helper and about six vote tests (`test_hook_appends_a_vote_id` to
  `test_unwritable_roll_log_still_emits_the_roll`) assume ids by default. They need `--votes`.
  Add one test that a bare hook run gives no id and creates no log file under a fake
  `XDG_STATE_HOME`. That pins the stranger default.
- Docs: add `--votes` and `ROLEPLAY_ROLL_LOG` to the README env table and to the Usage and env
  tables in `docs/claude-roleplay.md`. Say that the votes need a receiver outside `roleplay/`
  (the Hammerspoon `rolevote` seed), and that without one the flag is useless.
- Running sessions keep their old hook command until they restart or reload hooks.

**Smaller defect noticed, no action needed.** Ids are 4 base-36 characters, about 1.68 million
values. At about 100 rolls a day, repeats are near certain within a year: about 400 pairs.
`rolevote` takes the newest match, so a vote on an old reply could name the wrong character.
Votes are clicked within minutes, so the risk per vote is about 1 in 17,000 per day of delay.
The `rolled` column already lets an analysis spot it.

## 3. Hand runs write the real roll log: changed

**Diagnosis: true by the code.** A bare `roleplay-roll` (no argument) is hook mode, and hook
mode logs to `$XDG_STATE_HOME/roleplay/rolls.tsv`. The tests are safe, because `run()` sets a
fake `HOME` and `XDG_STATE_HOME`. **I could not verify the "20 + 1 rows".** The log now holds
23 rows, at most 3 in any one minute, with no burst. Either the rows were removed or the
count is wrong.

**Code change versus docs.** The signals I checked for "called by Claude Code" do not work.
I did not check every variable that only hooks get (for example `CLAUDE_PROJECT_DIR` is absent
from the Bash environment), but #2 needs a flag anyway:
- `CLAUDECODE=1` and the session ids are also set in every Bash-tool child.
- Reading stdin to look for the hook JSON is unsafe in a fail-open hook. In the Bash tool,
  stdin is a socket that never reaches EOF (see #4). So a hand run would hang.

The `--votes` flag from #2 is the code change. A hand run without it logs nothing. That also
covers a timing loop, unless the loop copies the hook command.

**Docs, still worth one line each:**
- Usage block in `roleplay-roll`: `roleplay-roll --votes  # what the hook calls: adds the vote
  id and writes the roll log; set ROLEPLAY_ROLL_LOG= for a test run`.
- `CLAUDE.md`, the `roleplay-roll` row: one clause, "only `--votes` (the hook) writes the roll
  log". This file has foreign hunks, so use Edit in that row only.

## 4. Live-loading a seed: changed

**The hang is explained and reproduced.** In the Bash tool, stdin is a socket
(`/dev/fd/0` is `srw-rw-rw-`). When stdin is not a terminal, `hs` reads it after it runs the
`-c` commands, and the socket never closes. Measured:
- `timeout 4 hs -c "return 1"`: exit 124 after 4.0 s, twice, with no output.
- `timeout 6 hs -c "return 1" </dev/null`: exit 0 in 0.01 s, three times.
- `hs -c '_retro_probe = "x"'` killed by `timeout` still set the global, as a second call with
  `</dev/null` showed. **So the command runs, and only the exit hangs.** A "hang, then retry"
  therefore runs `start()` twice.
- `hs -t` (default 4 s) bounds only the IPC send and receive, not the stdin read. It did not
  help.
- The brief says the retry "with timeout worked at once". That does not match: a
  `timeout 15` call without `</dev/null` should take 15 s and exit 124. This is unexplained.
  The retry may have had a different stdin.

**Rule to document:** always `hs -c '…' </dev/null`. Add `timeout` only as a backstop.

**"Safe only if start() can run twice" is the wrong condition.** The recipe clears
`package.loaded` and then calls `require`. This makes a new module instance, and the old one
keeps its timers, eventtaps and menubars. The old instance is still reachable, through the
global `seeds` table, and through `package.loaded` before it is cleared. A grep of `start()` and
the modules shows the scale. 20 of the 22 seeds create timers, hotkeys, eventtaps, watchers
or menubars. `monitor.lua` is an example: a second `start()` adds a second 20-second timer
and second eventtaps, so every log entry is written twice. Only `copylink` and `rolevote`
are safe, because `hs.urlevent.bind` replaces a callback by name. Also, `start({})` drops
the config that `hammerspoon.lua` passes, which is not empty for calendar, lotus, watch,
emoji, clipboard, cursor, battery and macro.

**Worse defect in the same code (read from the code, not tested).** Cmd+Ctrl+R is a **soft reload** (`softReload` in
`lib/lua/hammerspoon.lua`), not `hs.reload()`. It clears `package.loaded` only for a fixed
`seedModules` list, and it stops only the seeds in the `seeds` table. `seeds.copylink` and
`seeds.rolevote` are in neither. So after an edit to `copylink.lua` or `rolevote.lua`,
Cmd+Ctrl+R gets the cached old module from `require` and runs the old code again. Only the
hard reload (Cmd+Ctrl+Shift+R) loads the new code. That is probably why the session needed
the live trick. Fix: add both to `seedModules` and to the `seeds` table, next to
`livetranscribe`. `docs/hammerspoon.md` (about line 542) still describes the reload as the
flag file, `stop()` and `hs.reload()`. It does not mention the soft reload, so update it too.

**The "Never call hs.reload() programmatically" rule.** Its reason is not recorded. It came in
with commit `b8dda412`, a broad Hermes commit that gives no reason. A live-load does not call
`hs.reload()`, so it does not break the letter of the rule. It also leaves the other seeds
alone. I do not claim a contradiction.

**Revised CLAUDE.md text (Seed Architecture section), about 70 words:**

> - Cmd+Ctrl+R is a soft reload. It reloads only the seeds listed in `seedModules` and `seeds`
>   in `hammerspoon.lua`. Add a new seed to both.
> - To load a new seed without asking for a reload:
>   `hs -c 'package.loaded["seeds.X"]=nil; require("seeds.X"):start({})' </dev/null`. Without
>   the first statement, `require` returns the cached old code. Use this only for a seed that is not
>   loaded yet, or one whose `start()` only binds `hs.urlevent`. Always redirect stdin from
>   `/dev/null`: without it `hs` waits on the Bash tool's stdin forever, after it has already
>   run the command.

## 5. State the per-reply token cost: changed

**Diagnosis: true, but the number is old.** The "~400 tokens" was for the long form, before the
short-links commit (`dd657b34`). Now the eight links are 248 characters per reply. That is
about 100 output tokens, estimated at about 2.5 characters per token for URL-like text. I did
not count it with a tokenizer. The vote paragraph in `rcs/claude-user-claude.md` is 384
characters, about 100 input tokens per session. Output tokens cost more, and they also slow
every reply.

**Specificity.** "Before adding text to every reply or every prompt" is a weak trigger. The
model must notice that a design choice is per-reply. Name the usual vehicles, and ask for the
cheaper option. Proposed text, as its own short section after "Security trade-offs" (both are
rules for proposing automation):

> ## Per-reply cost
>
> When a change adds fixed text to every reply, prompt or session (a hook output, a CLAUDE.md
> rule, a reply format), state its size in tokens per reply before you build it. Say whether
> the text is input or output, and give the cheaper option if there is one.

This rule costs about 60 input tokens per session itself, which is acceptable.

## 6. XDG_STATE_HOME in rolevote.lua: rejected

**Diagnosis: true on paper, with no effect today.** Measured:
`hs -c 'return tostring(os.getenv("XDG_STATE_HOME"))' </dev/null` returns `nil`, and
`launchctl getenv XDG_STATE_HOME` is empty. Only fish sets it (`fish/conf.d/00_xdg.fish`), to
the same `~/.local/state` that the Lua code hardcodes. So the fix always takes the fallback.

**The real way the paths can diverge is not fixed by it:**
- `ROLEPLAY_ROLL_LOG` can move the hook's log, and Lua never sees it.
- A non-default `XDG_STATE_HOME` in fish would not reach Hammerspoon either.

**Smaller fix:** a one-line comment in `rolevote.lua` saying it assumes the default path, and
that `engage("seeds.rolevote", {rolls = …, votes = …})` overrides it. `start(cfg)` already
accepts both paths.

## 7. Automated tests for rolevote.lua: changed (low priority)

**Facts:**
- `lua` and `lua5.4` (5.4.8) are installed, and `brew 'lua'` is in the Brewfile. Hammerspoon
  reports `Lua 5.4`, so the version matches.
- `busted` is **not** installed, and no component uses it. `run_busted` returns no counts, so
  the aggregate summary would show nothing for it. Using busted means a new luarocks
  dependency on every machine, for a weaker summary.

**Revised fix:** a pytest file that runs `lua5.4` on a small Lua harness, with
`pytest.skip` if `lua5.4` is missing. This uses the runner every other component uses.

**Feasibility, tested.** A 20-line harness stubbed `hs.alert.show` and `hs.urlevent.bind`,
loaded the real `seeds.rolevote` with `votes` and `rolls` paths in a temp folder, and called
the bound callbacks directly. All four checks behaved as the code intends:
- With a duplicated id, the newest roll wins.
- An unknown id is recorded and the alert says so.
- Slot 9 gives "bad link".
- A tab and a newline in the long form become spaces.

Copylink can use the same stub (`hs.pasteboard.setContents`, plus the empty-text alert).

**Cost of registering:**
- One `COMPONENTS` entry in `lib/python/run_tests.py`, for example `"lib/lua"` with
  `runner: pytest`, `deps: []` and alias `hammerspoon`.
- One `tests/lib/lua/` directory.
- One row in the CLAUDE.md test table.

Both seeds are small, and a failure shows up at once as an alert on click. So this is
"nice to have". Do the reload-list fix in #4 first.

## Order of work

1. #4 reload list (`seedModules` and `seeds` in `hammerspoon.lua`): a real bug, small.
2. #2 and #3 together: the `--votes` flag, tests, settings command, docs.
3. #1 and #5: two short paragraphs in `rcs/claude-user-claude.md`.
4. #4 docs, #6 comment, #7 tests.

Effort: about 1 hour for 1 to 3, and about 45 minutes for 4.
