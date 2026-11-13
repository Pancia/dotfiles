# Critique: retro suggestions from the Live Transcribe session

Date: 2026-11-12. Read-only review. I did not run the engine, launch the app,
build into `bin/`, or use the mic or the clipboard. Behaviour tests ran only in
`/private/tmp/claude-501/-Users-anthony-dotfiles/38f27894-f54c-4b44-a482-45ef6940e592/scratchpad/critique/`
(`build/` for item 5, `wav/` for item 1). On `~/Cloud` I used only `stat`, `ls -lO`
and `find`. Nothing in ~/dotfiles was changed except this file.

## 1. Warn when the temp WAV vanished: CHANGED

**Diagnosis: true.** In `_finalize_recording`, `if not tmp or not tmp.exists(): return`
drops the audio and prints nothing.

**Would a stderr warning reach the user? No, not in the app.** I checked how
`main.swift` handles the pipe:

- **It is hidden by default.** `isDebugChatter` hides every non-transcript engine
  line unless it contains `error`, `traceback`, `exception`, `failed` or `fatal`.
  A line like "Warning: temp WAV ... is gone" has none of these words.
- **It is not styled as an error.** `styleLine` draws all non-transcript engine
  lines in `Palette.dim`. `Palette.errorFG` is used only by the app's own
  `appendError`.
- **The panel closes right after.** `finish` waits for the engine to exit, then
  `afterEngineStopped` calls `deliver` and `terminateNow`. The warning prints during
  the stop sequence, so it is on screen for a few seconds at most.
- **Two stop paths drop it completely.** `switchMic` (line 1143) and
  `applicationWillTerminate` set `readabilityHandler = nil` *before* they send
  SIGINT. The old engine's finalize output then reaches neither the panel nor
  `last.log`.
- **The only lasting copy is `last.log`,** and the next session empties it (item 2).

**False fires.** The second, idempotent call from `finally` is clean: `writer` and
`tmp` are both `None`, so it returns at line 712. A run without `--save-audio`
returns there too. But there are two wrong fires if the warning sits at the
existing `return`:

- If `wave.open` failed in `__init__`, `wav_tmp_path` stays set and no file exists.
  The new warning would say "vanished" for a file that never existed.
- The `frames == 0` check comes *after* the exists check. A vanished file with no
  frames would warn although nothing was lost.

Gate the warning on `frames > 0 and not tmp.exists()`. That covers both.

**What the fix would break: nothing found,** once it is gated as above. It adds one
line to the terminal output and `last.log`.

**Smaller fix:** none that reaches the user. The one-line engine warning is already
the smallest change, and it is not enough on its own (see above).

**Worse defects in the same code:**

- **A WAV kept after a failed transcode is deleted 14 days later, silently.** When
  ffmpeg fails, the code keeps `rec_<ts>.wav` in the state folder and prints
  "Saved audio to: <tmp>". That file is the only copy of the audio. The start-up
  sweep globs `rec_*.wav` and deletes files idle for 14 days, so the next
  `--save-audio` start after 14 days deletes it. In the app the user never sees the
  "Saved audio to" line (no keyword, panel closes). Fix: on ffmpeg failure, rename
  the file to `kept_<ts>.wav`, which the sweep glob does not match.
- **"Warning: could not open audio recording file" is also hidden.** It has no
  keyword, so a session that records no audio from the start is already silent.
- **Minor.** `rec_<ts>.wav` and `transcript_<ts>.txt` use one-second stamps.
  Two engines started in the same second open the same files with `'wb'`/`'w'` and
  truncate each other. Low odds. Adding the pid to the names closes it.

**The audio is recoverable, tested.** The engine still holds the WAV open when the
path is deleted. Writes keep going to the unlinked file, and `writer.close()`
patches the header without error. In scratch I opened the file with
`open(path, 'w+b')` and passed that object to `wave.open(f, 'wb')`. `wave` does not
close a file it did not open. After an unlink mid-write, `f.seek(0)` and
`ffmpeg -f wav -i pipe:0` with `stdin=f` produced an .m4a of the full length (6.0 s
of 6 s), including the frames written after the unlink. This is about six lines.
The root cause (the sweep) is already fixed, so this is optional hardening against
any other deleter.

**Revised fix, in order of value:**

1. Rename a WAV kept after an ffmpeg failure to `kept_<ts>.wav`, so the sweep
   cannot take it.
2. Make audio loss visible outside the panel. After the engine exits, the app
   checks each non-empty `transcriptPaths` entry for its sibling `.m4a`. If one is
   missing, it posts a macOS notification (transcript-pick already uses
   `terminal-notifier`), naming the kept WAV if there is one. This check does not
   depend on engine output, so it also covers the `switchMic` path and a SIGKILL.
3. In the engine, warn when `frames > 0 and not tmp.exists()`, with a keyword the
   filter shows, for example "Warning: saving audio failed: <tmp> was deleted
   during the session". Add "failed" to the could-not-open warning too. This
   helps the terminal and `last.log`, not the panel.
4. Optional: the `w+b` handle and transcode from the open file, as tested above.

## 2. Per-session logs: CHANGED (smaller design)

**Diagnosis: true.** `startEngine` calls `createFile(atPath: logFilePath, contents: nil)`
when `logHandle == nil`, which empties `last.log` at each session start. A mic
switch takes the other branch and appends, on purpose.

**Readers of last.log: none.** It appears only in `main.swift` (lines 93, 1344,
1395). Nothing in `bin/live-transcribe-launch`, `lib/lua/seeds/livetranscribe.lua`,
`docs/`, `wiki/`, `ai/`, `fish/`, `lib/` or `~/.claude/{skills,commands,agents}`
reads it. So no symlink or copy is needed for a program. Only a human habit uses
the name.

**Smallest safe design.** In the `logHandle == nil` branch, before `createFile`:
if `last.log` exists and is not empty, rename it to `session_<ts>.log`, with
`<ts>` from its creation date (that is the previous session's start). On the
current file, `stat -f '%SB %Sm'` gives birth 18:00:26 and modified 18:00:55, so
the birth time does mark the session start. The modification date also works if
the name should mean "session end". Then list
`session_*.log`, sort by name, and delete all but the newest 20. Then create
`last.log` as now. About ten lines. Everything else stays the same: `last.log` is
always the current session, the mic-switch append path is untouched, and nothing
needs a symlink. The log already contains "Writing transcript to: ...", which
links each session log to its transcript.

**What it would break: nothing found.** One cost: the log tees every transcript
line, so 20 logs keep 20 extra local copies of transcript text in
`~/.local/state`. That is local and small, but say so in a comment.

**Worse defects in the same code:**

- **The log loses the old engine's shutdown on a mic switch.** As in item 1,
  `switchMic` and `applicationWillTerminate` detach the reader before SIGINT. So
  the old engine's "Saved audio to", "Transcript saved to" and any finalize warning
  never reach `last.log`. That is exactly the part a lost-audio investigation
  needs. Fix: keep the reader attached until the old process exits, then detach.
- **Possible, not tested:** in the normal stop path, `afterEngineStopped` detaches
  the reader right after the exit. Bytes still in the pipe at that moment can be
  lost from the log.
- **Known API behaviour, not tested here:** `FileHandle.write(_: Data)` raises an
  Objective-C exception on an I/O error (for example, a full disk). Swift cannot
  catch it, so the app would crash mid-session. `try write(contentsOf:)` throws a
  normal Swift error instead.

## 3. A Live Transcribe section in CLAUDE.md: CONFIRMED (with corrections)

**Diagnosis: true.** CLAUDE.md has no Live Transcribe section. The only nearby
text is "Warm Whisper Server with Idle TTL (whisper-serverd)", which describes the
server that the engine uses. `docs/hammerspoon.md` has one row for the menu-bar
seed. `wiki/pages` has nothing. `.cc/pending-updates-20261112-141134-cf309d20.md`
does not overlap.

**Best place.** Put a new `### Live Transcribe` section directly above the
whisper-serverd section in CLAUDE.md, so the two read as one topic. Ten lines do
not justify a new doc in `docs/`.

**Corrections to the proposed facts:**

- The Makefile uses the certificate only when it is in the keychain. Otherwise
  it signs ad hoc, says nothing, and the mic permission resets.
- The engine's default output folder is `~/transcripts`, a symlink to
  `ProtonDrive/transcripts/`, the same folder as `~/Cloud/transcripts`. A test run
  without `--output-dir` writes into the synced folder and into the history lists.
  The recipe must require `--output-dir`.
- "Never while the app runs" is now a precaution, not a hard rule. With the sweep
  fixed and no `--save-audio`, a test engine cannot delete a live recording. It
  still uses the shared warm whisper server (default mode), so it slows the live
  session. `--ephemeral` isolates it, at the cost of a second model load.
- A rebuild while the app runs does not crash it (item 5). That is worth one
  clause, so a later session does not re-derive it. I did not test the mic
  permission after a rebuild, so the draft does not say "safe".
- `pgrep -f live-transcribe-app` also matches any process whose arguments hold
  that string, such as `make -C cmd/live-transcribe-app` or an editor on
  `cmd/live-transcribe-app/main.swift`. Use `pgrep -f LiveTranscribe.app/Contents/MacOS/`,
  which matches only the app binary. (Nothing was running when I checked, so this
  comes from how `pgrep -f` matches, not from a seen false match.)

**What it would break: nothing.** The cost is about ten more lines in a file that
every session in this repo loads.

**Smaller fix:** drop the history line and the paths that a `grep` finds in a few
seconds. Keep the signing, the output-folder and the test-recipe lines. Those are
the facts that cost time or data when they were missing.

**Worse defect:** none in the docs. The defects found are in items 1 and 2.

**Draft text:**

```markdown
### Live Transcribe

- Engine: `bin/live-transcribe` (Python). App: `cmd/live-transcribe-app/main.swift`, built into `bin/LiveTranscribe.app` by `./install lta`. A rebuild does not crash a running app; restart the app to load it.
- The Makefile signs with the "LiveTranscribe Self-Signed" certificate, so the mic permission survives a rebuild. Without it, the build signs ad hoc and macOS asks for the mic again.
- Transcripts and their `.m4a` go to `~/Cloud/transcripts` (ProtonDrive). `~/transcripts` is the same folder and is the engine's default.
- Logs: `~/.local/state/live-transcribe/last.log`, emptied at each session start. The temp recording `rec_<ts>.wav` is there while a session records.
- History: the clock pull-down in the panel, the menu-bar "Recent Transcripts" submenu, and `bin/transcript-pick` (⌘Space → u → t).
- To test the engine, use BlackHole as the mic and an `--output-dir` in the scratchpad. Never pass `--save-audio`. `.cc/scripts/live-transcribe-tail-repro.sh` does this.
- Check `pgrep -f LiveTranscribe.app/Contents/MacOS/` first. A test run shares the warm whisper server and slows a live session.
```

If item 2 lands, change the log line to "`last.log` is the current session;
`session_<ts>.log` keeps the 20 before it."

## 4. The ~/Cloud dataless trap: CHANGED (wording and place)

**Diagnosis: true, but "most files under ~/Cloud" is too broad.** What I measured:

- `~/Cloud/transcripts`: 1,293 entries, 1,167 `compressed,dataless`. Of 697
  `.txt` files, 590 are dataless and 107 are local.
- Other folders vary. `_inbox` (19), `_config` (4), `_reference` (10) and
  `_spirituality` (22) are all local. `AKR` has 18 of 22 dataless, `_AI` 2 of 2.

So write "many files", not "most".

**Does `stat` download? No.** On `transcript_2025-11-27_23-37-36.txt` I ran `stat`
twice, `stat -L`, `ls -lOu` and `find -flags`. After each one the flags stayed
`compressed,dataless` and the allocated blocks stayed 0. That is the real
evidence. The atime (01:59:32) also did not change, but that is weak evidence on
its own. The logical size still shows (84 bytes), so a size-0 test still works on
a placeholder. I did not test whether listing a folder that is itself dataless
fetches anything.

I did not read a dataless file, as instructed. So "reading one downloads it" is
not from my test. It comes from the session (the 2-minute picker hang) and from
`.cc/reports/REVIEW-live-transcribe-tail-and-history.md`. It is also the documented
File Provider behaviour.

**The code already does this.** `bin/transcript-pick` (`stat -f '%Sf…'`) and the
app's `transcriptPreview` (`lstat` and `SF_DATALESS`) both check the flag before
they read. The missing piece is only the note for later sessions.

**Better check for bulk work.** `find DIR ! -flags +dataless` lists only local
files in one call, and does not download. Tested: it returned 107, which matches
697 − 590.

**Better place.** `~/Cloud` is not specific to dotfiles: it holds folders such as
`AKR`, `altera-project` and `claude-transcripts`, which other projects probably
use. If they do, put the line in the global file, `rcs/claude-user-claude.md`
(MANIFEST maps it to `~/.claude/CLAUDE.md`). That file already shows as modified
in the working copy, so commit only this line. If you want the global file kept to
reporting rules, use the dotfiles CLAUDE.md instead.

**What it would break: nothing.** One line of load in every session.

**Smaller fix:** none. It is one line.

**Worse defect:** none found. Both readers already guard against the trap.

**Draft line:**

```markdown
Many files under `~/Cloud` (ProtonDrive) are cloud-only placeholders: `stat -f %Sf` shows `dataless`. Reading one downloads it, so a bulk read can hang for minutes. `stat`, `ls -lO` and `find` do not download. Before reading many files there, select local ones with `find DIR ! -flags +dataless`.
```

## 5. Makefile refuses to build while the app runs: REJECTED

**Diagnosis: false.** Both build steps replace the file with a new inode. Neither
writes into the file the running process uses. Test in scratch: a 40-second Swift
loop in `T.app/Contents/MacOS/live-transcribe-app`, signed and running, then the
Makefile's two steps on it:

| Step | Inode before → after | Process |
|---|---|---|
| `swiftc -O -o <bin>` (different code) | 785841724 → 785841780 | alive |
| `codesign --force … T.app` | 785841780 → 785841785 | alive |

The process ran to its normal end ("survived", exit 0). A running process keeps
its old inode mapped, so a new inode cannot change its code pages. That is the
evidence, not the survival itself.

**Limits of the test:**

- My control was inconclusive. I wrote a different binary *into* the same inode
  (`cat other.bin > <bin>`), and the process survived that too. Its code pages were
  probably already resident. So survival alone does not show safety; the inode
  change does.
- I signed ad hoc (`--sign -`), not with the "LiveTranscribe Self-Signed"
  certificate, to avoid a keychain prompt. codesign uses the same write path for
  both, but I did not verify that with the certificate.
- I did not test whether a running app still passes the mic permission check
  after its bundle on disk is re-signed. A mic switch starts a new engine, so that
  check can run after a rebuild. With the certificate, the designated requirement
  does not change, so I expect no effect, but that is not tested. With the ad-hoc
  fallback it could matter.

**What the guard would break.** It would block `./install all` and every rebuild
during a session. The task's criterion was a crash, and there is none. The running
app keeps the old code until restart.

**Smaller real issue in the same Makefile.** When the certificate is missing, the
`CODESIGN_IDENTITY` fallback signs ad hoc and prints nothing, which resets the mic
permission. The comment says a bare `make` "never silently resets" it, but that
holds only while the certificate exists. Add a `$(warning ...)` on the ad-hoc
branch. Optionally the recipe can print "LiveTranscribe is running; restart it to
load this build" when `pgrep -f live-transcribe-app` succeeds. That is a notice,
not a refusal.

## Summary

Item 1 is changed. The diagnosis is right, but a stderr warning is hidden by the
panel's filter, the panel closes at once, and a mic switch drops the line. The
higher-value fixes are: protect a WAV kept after a failed transcode from the
14-day sweep, and have the app post a notification when a session ends without
its .m4a. The warning itself should be gated on `frames > 0` and use a word the
filter shows.

Item 2 is changed to a smaller design. Nothing reads `last.log`, so rotate the old
file to `session_<ts>.log` at session start and keep 20. No symlink is needed.
Separately, a mic switch detaches the log reader before the old engine finishes.

Item 3 is confirmed, with a draft. It must say that `--output-dir` is required,
because the engine's default folder is the synced transcripts folder. It should
also call the "app not running" rule a precaution.

Item 4 is changed. The trap is real and `stat` does not download, but "most
files" overstates it. The line belongs in the global CLAUDE.md, and should offer
`find DIR ! -flags +dataless`.

Item 5 is rejected. `swiftc -o` and `codesign --force` both write a new inode, so
a rebuild does not crash the running app. The test signed ad hoc, and did not
check the mic permission after a re-sign. The only fix worth taking from it is a
warning when the build falls back to ad-hoc signing.
