# Review: media-sync (vault script + launchd service)

Reviewed 2026-11-12. Files: `~/AKR/scripts/media-sync`, `~/AKR/tools/media-sync/*`,
`services/media-sync/*`, `bin/open-iterm-with`, `fish/config.fish` (`_ENSURE_SERVICES`),
`~/AKR/.cc/scripts/media-sync-rename.py`. Evidence: the run logs in
`~/.local/state/media-sync/runs/`, `~/.log/services/media-sync.log`, the gallery-dl 1.29.2
source, and the two permitted dry runs. Nothing was downloaded or sent.

Most severe first.

## 1. A Pinterest source that fails completely is reported as "ok" — CONFIRMED

`scripts/media-sync:129` treats gallery-dl exit 4, 8 and 12 as success. Those bits do not only
mean "a few old pins 403":

- exit 4 (`HttpError`) is also what gallery-dl raises when the **whole request** fails:
  no network (`ConnectionError`, retried, then `raise exception.HttpError`,
  `extractor/common.py:174-241`), Pinterest 5xx, or repeated 429.
- exit 8 (`NotFoundError`) is what the Pinterest API wrapper raises on a **404 for the user or
  board** (`extractor/pinterest.py:532-534`), i.e. a renamed or deleted profile/board.

Scenario: the account `anthonyytsq` is renamed, or the Mac has no network when the job fires.
gallery-dl exits 8 or 4, the log says `pins: ok, 0 new file(s); some old pins could not be
fetched`, the success notice and Telegram go out, and the board is never mirrored again with no
alert. The "some old pins" text appears on every healthy run too (both real runs today ended
with exit 4), so nobody would notice the difference.

Fix: decide from the output, not the exit bits. Per-pin failures are logged by the download job
as `[download][error] Failed to download ...` (`job.py:348`); extractor-level failures are logged
through the extractor's logger as `[pinterest][error] HttpError: ...` / `NotFoundError: ...`
(`job.py:157-163`). Today's healthy run has zero `[pinterest][error]` lines. So: accept 4/8/12
only when `re.search(r"^\[pinterest\]\[error\]", output, re.M)` finds nothing; otherwise fail.

## 2. One permanently unavailable video fails the source on every run — CONFIRMED (exit), PLAUSIBLE (trigger)

`scripts/media-sync:134` fails the source on any non-zero yt-dlp exit. With `--ignore-errors`,
yt-dlp still exits 1 if any single entry errored — seen today: `druids: FAILED (exit 1), 34 new
file(s)` (17:05 run) for two age-gated videos while 34 others downloaded. Failed entries never
enter the archive, so they are retried, and fail, on every run.

Scenario: a channel posts a members-only video, a scheduled premiere ("Premieres in 2 days"),
or a region-blocked/claimed upload. Every Tuesday and Friday from then on: a "Media sync FAILED"
notification, a fix-prompt, and a Claude Code bot Telegram message, until someone edits the
archive by hand. A premiere nags until it airs; members-only nags forever.

Fix: classify the `ERROR:` lines. Treat the channel itself as failed only if listing failed (no
`Finished downloading playlist` line, or an `ERROR: [youtube:tab]` line). For per-video errors,
either ignore known permanent classes (members-only, private, unavailable, upcoming/premiere,
"not available in your country"), or keep a small state file of failing IDs and alert only when
that set changes. `--ignore-no-formats-error` also turns the premiere case into a warning.

## 3. No timeout on any download; a hang silently stops all future runs — PLAUSIBLE

`_stream` (`scripts/media-sync:140-149`) waits for the child with no limit, and `script.sh:65`
waits for media-sync with no limit. launchd never starts a second instance of a job that is still
running, so a wedged yt-dlp/gallery-dl (stalled HTTP read on a sleeping network, a stuck File
Provider write, or the keychain prompt in finding 4) means: no end notice, no Telegram, and every
later Tue/Fri slot is skipped silently. The "Started" notice is the only trace.

Fix: `p.wait(timeout=...)`-style limit per source (read the pipe in a thread, or run under
`timeout`), kill the process group on expiry, and log it as `FAILED (timeout)`.

## 4. The age-restriction retry is untested under launchd and can block on a keychain prompt — PLAUSIBLE

`scripts/media-sync:122-124` reruns yt-dlp with `--cookies-from-browser brave`. On macOS yt-dlp
decrypts Brave's cookies with `security find-generic-password -s "Brave Safe Storage"`; unless
that keychain item already trusts `/usr/bin/security`, macOS shows an "allow access" dialog and
the call waits for a click. At 10:00 with nobody at the desk, combined with finding 3, the run
hangs indefinitely. The path has not run yet: the 17:05 run predates the retry code, and the two
age-gated druids videos were in the archive by 17:13 (fetched by hand), so the 17:13 run never
reached the retry.

Also: if Brave is signed out of YouTube or its cookies expire, the retry fails too and finding 2
applies every run.

Fix: put a timeout on the retry (finding 3), and test the path once from launchd (for example
remove one age-gated ID from `druids-grove/_downloaded.txt` and its file, then run the job with
`launchctl kickstart`) to confirm the keychain item is already allowed.

## 5. Run fires on wake before the network is up — PLAUSIBLE

The plist comment is right that a missed calendar slot runs on wake; launchd fires it within
seconds of wake, often before Wi-Fi rejoins. Result: every YouTube source fails (notification +
fix prompt), the Telegram `curl` fails as well, and Pinterest is reported "ok" (finding 1).

Fix: in `script.sh`, before the "Started" notice, wait up to a few minutes for connectivity (e.g.
loop on `/usr/bin/curl -fsS -m 5 -o /dev/null https://www.youtube.com` with a sleep), and run
anyway after the deadline.

## 6. File names can exceed the 255-byte limit — PLAUSIBLE

`NAME_TEMPLATE` (`scripts/media-sync:43`) has no length bound. Existing names already reach 195
bytes (druids, IvyWilde). The markers cost 18 bytes, yt-dlp turns `|` into the 3-byte `｜`, and
these titles are full of 4-byte emoji. A YouTube title of 100 characters, or a long soundgasm
title, passes 255 bytes; yt-dlp then fails that item with `File name too long`, which by finding 2
fails the run on every schedule.

Fix: `%(title).150B` in the template (byte-limited field), or add `--trim-filenames 240`.

## 7. Success sends a Telegram message and notification every run, even with nothing new — CONFIRMED

`script.sh:79-84` always sends "Media sync done" to Inari. Because pins exits 4 on every healthy
run, every message includes "some old pins could not be fetched (exit 4)". Twice a week, forever,
mostly "0 new file(s)". That teaches the reader to ignore the channel that would carry a real
problem. Suggested: send the Telegram message only when at least one source added files, and drop
the exit-4 wording from the success summary.

## 8. Telegram failures are invisible — CONFIRMED

`script.sh:48-51`: a failed `curl` only echoes to the service log. On the failure path, if the
send fails (finding 5), the only alert left is the macOS notification. Low; consider including
"Telegram send failed" in the notification text when it fails on the failure path.

## 9. Click commands are correct for today's paths but break on any quote, `$` or space — CONFIRMED (correct now) / PLAUSIBLE (break)

Traced with a printing stub of `open-iterm-with` through `/bin/sh -c` (terminal-notifier runs
`-execute` via `/bin/sh`):

- start: `fish -c 'tail -n +1 -f /Users/anthony/.local/state/media-sync/runs/<ts>.log'` — correct.
- failure: `fish -c 'cd /Users/anthony/AKR; and claude (cat .../fix-prompt.md | string collect)'`
  — correct; the `\\;`, `\\(`, `\\|` escapes survive sh and land as fish syntax.

The ProtonDrive `@` path never reaches either command. But `open-iterm-with` pastes `$*`
unescaped inside an AppleScript `"..."` string inside fish `'...'`, and `script.sh` pastes
`$runlog`/`$prompt_file` unquoted into a sh string. Any `XDG_STATE_HOME` containing a space, `'`,
`"`, `\` or `$` breaks the click (wrong args or an AppleScript syntax error, both silent). Low
risk today. Robust fix: have `script.sh` write the click action as a small fish script in
`$state/` and pass only that fixed path to `open-iterm-with`.

## 10. Dry mode overwrites the real fix prompt — CONFIRMED

`script.sh:88` writes `$state/fix-prompt.md` even when `MEDIA_SYNC_DRY=1`. Running the documented
test (`MEDIA_SYNC_DRY=1 MEDIA_SYNC_CMD=/usr/bin/false`) replaced the prompt a real failure had
left, which a pending Telegram "Read .../fix-prompt.md" message still points at. (I restored the
original after my dry run.) Fix: use `fix-prompt.dry.md` in dry mode, or print it instead.

## 11. `_ENSURE_SERVICES`: removal is safe; "load" does not reload a changed plist — PLAUSIBLE

`fish/config.fish:24-26`. Removing `launchctl start` is right for media-sync: it has no
`RunAtLoad`, so a plist relink no longer triggers a download run. Every other plist has
`RunAtLoad`, `KeepAlive` or a schedule, so nothing depended on the start. Remaining gap (old, not
new): `launchctl load` on a job that is already loaded is a no-op ("service already loaded"), so a
plist edit (for example a new media-sync schedule) is not applied until `service restart
media-sync`. The comment slightly overstates what `load` does; `rcs-sync` already prints the
restart reminder.

## 12. Renamer can corrupt the archive's last line — PLAUSIBLE

`media-sync-rename.py:55-57` appends to `_downloaded.txt` without checking that the file ends with
a newline. yt-dlp always writes a newline, so this needs a hand-edited archive; then the first
added ID joins the last line and both items are downloaded again. Fix: prepend `"\n"` when the
existing text is non-empty and does not end with one.

## Checked and fine

- launchd environment: the 17:13 run went through `service-wrapper` and succeeded; `uv` is at
  `/opt/homebrew/bin`, a managed Python 3.11 satisfies `requires-python`, no dependencies to fetch.
- Lock: exit 75 handled; launchd never overlaps the job itself.
- Summary parsing (`script.sh:69-80`): yt-dlp/gallery-dl lines cannot match the timestamp regex;
  `( )` are literal in BSD sed BRE; `done, failed:` is excluded from `failed` (case-sensitive).
- Telegram: all three keys exist once, no `export` prefix, no inline comments; HTML escaping
  covers `& < >`; messages are far below 4096 characters.
- gallery-dl `-c` with `base-directory: ./` works because `cwd` is the destination.
