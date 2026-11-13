# Review: live-transcribe tail fix and transcript history (jj change pyuxplurwuyz)

Read-only review. Reviewed the committed versions of the files (`jj file show -r pyuxplurwuyz`)
in full, not only the hunks. Line numbers below are in the committed files.

Checks run:
- `python3 -c 'import ast; ...'` on `bin/live-transcribe`: parses.
- `bash -n bin/transcript-pick`: clean.
- `rcs/hermes-commands.json`: valid JSON; `u` now holds `l` and `t`, no key clash.
- `swiftc -O main.swift` (same flags as the Makefile) into the scratchpad: builds; only a
  pre-existing deprecation warning at line 1683.
- `bin/transcript-pick --list` against the real `~/Cloud/transcripts`: 0.06 s, 625 rows.
- `ls -lO` on the real folder: 1,291 entries; 1,167 are `compressed,dataless`, 124 are `-`.
  The newest dataless transcript is `transcript_2026-11-06_13-29-50.txt`, six days old.
- Small shell tests of bash 3.2 vs 5 `${f/#$HOME/~}`, `paste`/`tr`, and macOS awk `substr`.

Not run (per brief): the engine, the repro script, the app, and the picker's
`--open` / `--copy-text` / `--audio` / interactive modes. Everything about runtime
behaviour of the engine and the Swift UI below is inferred from code unless it says
"verified".

Labels: **verified** = observed by a command; **inferred** = reasoned from the code.

---

## Findings, most severe first

### 1. Medium (inferred): the app now reads up to 10 cloud transcripts on the main thread at launch, before the engine starts
`cmd/live-transcribe-app/main.swift:768` calls `rebuildHistoryMenu()` inside
`buildControlBar`, which runs from `buildPanel()` at line 495, before `startEngine()` at
line 498. `rebuildHistoryMenu` -> `fillRecent` -> `recentTranscriptItems` ->
`transcriptLabel` -> `transcriptPreview` (line 1286) opens each file and reads 512 bytes.

Reading a dataless File Provider file downloads it (the premise of `transcript-pick`).
Verified: dataless transcripts exist as recent as 2026-11-06; today the 40 newest non-empty
files are all local, so it has not bitten yet. Failure scenario: once one of the 10 newest
is evicted, or arrives from another device as a placeholder, a hotkey launch blocks on a
download before the mic opens, and speech in that time is lost; offline, the launch can
stall until the read fails. Before this commit the same reads ran only when the status
menu's "Recent Transcripts" was opened, never on the recording-start path. The pull-down's
rebuild on open has the same exposure, but that is user-initiated.

The comment at lines 1283-1285 still calls the folder "today a plain local directory",
which contradicts the new script's comment.

Fix options: do not call `rebuildHistoryMenu()` at build time beyond adding the face item
(the delegate rebuilds on open); and in `transcriptPreview` skip files whose `st_flags`
has `SF_DATALESS` (or check `ubiquitousItemDownloadingStatus`), as the script does.

### 2. Medium (inferred from code): the repro script cannot reproduce the bug it was written for
`.cc/scripts/live-transcribe-tail-repro.sh:15` starts the engine without `--save-audio`.

The old bug needs a gap between `running = False` and `_flush_buffers()` long enough for
the worker's 1 s `get()` poll to time out on an empty queue. In the old code
(`pyuxplurwuyz-`) the only work in that gap was `_finalize_recording()`. Without
`--save-audio` it returns at once (`writer is None and tmp is None`), so the gap is a few
microseconds. If the worker is busy on a chunk instead, it re-checks the queue after the
flush has landed. Either way the old engine keeps the tail almost every time.

Failure scenario: running the repro against the old engine shows the last sentence, so it
"confirms" nothing, and a future regression of this kind also passes. The commit message
itself names the transcode as the trigger. Not run, per the brief.

The comment at lines 7-8 ("every engine start deletes ALL rec_*.wav") is stale after this
same commit: the sweep now takes only files older than 14 days, so adding `--save-audio`
is now safe, and it is needed.

### 3. Low-Medium (inferred from fzf's documented preview behaviour; not run): moving the cursor in the picker downloads cloud-only transcripts
`bin/transcript-pick:68`, `--preview="'$self' --preview {2}"`, and `--preview` runs
`cat "$f"` (line 47). fzf runs the preview for whichever row has focus, including the first
row at start and every row the cursor passes or a query floats to the top. So browsing the
list downloads each ☁ file it lands on, and offline the preview pane hangs on `cat` (fzf
kills the old preview when focus moves, so the UI itself stays responsive). The script's
comment ("downloads only when previewed or opened") is accurate, but this means the list,
which is careful never to read a dataless file, does read them as soon as the user scrolls
through them. So the answer to "does any part of it read a dataless file" is yes: the
preview does, without an explicit action. If that is unwanted, have `--preview` check the flags first
(`ls -lO "$f" | grep -q dataless`) and print "☁ press ctrl-p to download" or similar, with
the read behind an explicit key.

### 4. Low (inferred): the history pull-down stays enabled while a session is finishing, and a click there can move the auto-paste target
`main.swift:891-893`, `setControlsEnabled(false)` (called by `finish()` at 1648) disables
the mic picker, options, checkboxes and buttons, but not `historyPopup`. During the up to
10 s engine drain, clicking a history entry runs `openTranscript` (1320): it puts a
reference on the clipboard (later overwritten by `deliver()`, so harmless) and opens the
file. TextEdit becomes frontmost, `appActivated` (596) sets `targetApp` to it, and
`afterEngineStopped` then auto-pastes the session transcript into that old transcript's
window (plus Return, with "+ Enter"). The comment at 1316-1319 accepts this for a stop
issued while the file is frontmost, but here the user has already stopped and cannot
correct it. The status menu's "Recent Transcripts" submenu has the same exposure, so this is
consistent with existing behaviour; the new button just puts it next to Complete. Adding
`historyPopup` to `setControlsEnabled`, or ignoring `appActivated` while `finishing`,
closes it.

### 5. Low (verified): the picker orders entries within the same minute by preview text, not by time
`bin/transcript-pick:43`, `| sort -r` sorts the whole line, which starts with a
minute-resolution stamp. Verified on real data: `transcript_2026-11-12_10-07-07.txt` is
listed above `transcript_2026-11-12_10-07-44.txt`. The header says "newest first by
FILENAME". Fix: `sort -t$'\t' -k2,2r` (sort on the path field).

### 6. Low (verified): file names containing a space are silently left out of the picker
`bin/transcript-pick:31`, the awk test uses `$NF` as the file name. Verified: 17 real files
such as `transcript_2026-09-13_04-03-19 (# Edit conflict 2026-09-13 0t2shMC #).txt` have
`$NF` = `#).txt`, so they never appear (679 matching names vs 696 `.txt` files). The app's
menus (`hasPrefix`/`hasSuffix`) do include such names, so the two lists disagree. These are
ProtonDrive conflict copies, so leaving them out may be acceptable, but it happens by
accident of parsing, and a real transcript with a space would vanish too.

The other column assumptions hold (verified): field 5 is the flags (`-` or
`compressed,dataless`), field 6 the size, and the date is always three fields whether it
shows a time or a year. A `-` flags value is handled correctly: the file is local and its
first line is read.

### 7. Low (verified): the `read ~/...` string depends on bash 3.2 behaviour
`bin/transcript-pick:50,52`, `"read ${f/#$HOME/~}"`. `/bin/bash` 3.2 keeps the `~`
literal (correct: `read ~/Cloud/...`); Homebrew bash 5 expands it to
`read /Users/anthony/Cloud/...`. The shebang is `/bin/bash`, so it works today; running it
as `bash transcript-pick` with Homebrew bash first on PATH copies the long form. Safer:
`"read ~${f#"$HOME"}"`.

### 8. Low (inferred): orphan WAVs now persist up to 14 days, and a kept WAV is the only audio copy
`bin/live-transcribe:130-136` with `_finalize_recording` at 738-742. A `rec_*.wav` is left
behind by a SIGKILL during the ffmpeg transcode (the app SIGKILLs after 10 s), and by an
ffmpeg failure, where the code keeps the WAV on purpose. Before, the next engine start
deleted them; now they stay for 14 days, about 115 MB per recorded hour each. That is a
bounded leak, and better for the ffmpeg-failure case, which used to lose its "kept" WAV at
the next start. But after 14 days that WAV, the only audio copy, is deleted without notice.
Nothing else breaks: a live session's WAV is written on every callback through an 8 KB
buffer, so its mtime stays current and the sweep cannot take it.

### 9. Low, pre-existing (inferred): a second SIGINT during the drain can orphan an ephemeral whisper-server
`bin/live-transcribe:808-820`. If a second SIGINT lands during `transcription_thread.join()`,
`finally` runs `_stop_server()` while chunks remain queued. In `--ephemeral` mode the
worker's next POST fails, `_ensure_server()` (495) restarts a private server from the worker
thread, and nothing stops it. The old code had the same path, and the app uses the shared
warm server, so this is not a regression. A tiny related window: a second SIGINT inside
`_flush_buffers` between `self.mic_buffer = []` and `put` drops that chunk.

### 10. Cosmetic (verified): preview text can be cut mid-character; `|| true` hides a missing fzf
- `bin/transcript-pick:39`, macOS awk's `substr` counts bytes. Verified: `"a" + 60×"é"`
  cut at 90 ends with a stray `\303` byte, which fzf shows as a replacement character.
- `bin/transcript-pick:74`, the trailing `|| true` also swallows exit 127 if `fzf` is not
  on PATH, so the Hermes terminal closes with no message.

---

## Checked and fine

Engine shutdown (`bin/live-transcribe`), inferred from code:
- The diagnosis is right. In the old order (`running = False`, transcode, flush, join), a
  worker whose 1 s poll expired during the transcode exited on an empty queue, and the
  flushed tail was never transcribed.
- The new order is correct. The streams are stopped when the `with` block exits, so no
  callback can enqueue after `_flush_buffers()`. `_input_done.set()` follows the flush in
  the same thread, and `Queue`/`Event` both take locks, so a worker that sees the event set
  also sees the flushed items. `not done or not empty` drains until both hold. No early
  exit and no dropped chunk on the normal path.
- SIGINT before the streams open, during stream construction or during `sd.sleep`: caught
  by the inner `except KeyboardInterrupt`, then the same flush/set/finalize/join path.
- Any other exception (for example a PortAudio error opening the device): `finally` now sets
  `running = False` and `_input_done`, so the non-daemon worker exits within 1 s. The old
  code never cleared `running` there, so that process hung forever; this commit fixes it.
- A second SIGINT during finalize or join: `finally` still sets the event, and
  `_finalize_recording` is idempotent (it nulls `wav_tmp_path` under the lock), so there is
  no double transcode. The interpreter then waits for the worker to drain, which ends.
- The process cannot fail to exit because of this change: every path reaches `finally`,
  which sets the event. The worst case per remaining chunk is the existing network timeouts.
- The worker now transcribes the tail while ffmpeg runs, so the tail is more likely to land
  inside the app's 10 s SIGKILL window.
- The changed print order ("Flushing..." before "Saved audio to:") does not matter to the
  app: `handle()` keys only on "Writing transcript to:", the `[mic] [` meter prefix and the
  green banner escape. Tail transcript lines that arrive during the transcode are handled
  like any other line.

Swift (`cmd/live-transcribe-app/main.swift`); the build is verified, the rest inferred:
- Pull-down semantics: item 0 is the face (SF Symbol, or the emoji before macOS 11) and is
  not listed; entries start at item 1. Same pattern as the existing options pull-down.
- Item actions: each entry has `target = self` and its own selector (`openTranscript(_:)`,
  `openTranscriptsFolder`), so they fire from a pull-down that has no action of its own.
  `autoenablesItems = false` with the default `isEnabled = true` keeps them clickable, and
  the "No earlier transcripts" row is explicitly disabled.
- Delegate dispatch: `menuNeedsUpdate` checks `historyPopup` before the status-menu
  fall-through, so the status code cannot rename item 0 to "Hide Panel". The status
  submenus have no delegate, so they never reach this method.
- Nil at build time: `historyPopup = hist` is set before `rebuildHistoryMenu()`; an
  `NSPopUpButton` always has a menu; the method uses only `transcriptPaths` (empty),
  `cloudTranscriptsDir`, `transcriptRegex` and the static formatters, all initialised by
  then.
- `fillRecent` keeps the old empty-list behaviour and adds the separator and the folder
  item to both menus. Visibility priority 500 sits above the checkboxes and below the
  required buttons, as the comment says.

transcript-pick:
- `--list` reads no dataless file: only rows whose flags lack `dataless` reach `getline`
  (verified by timing, 0.06 s over 1,291 entries).
- `set -euo pipefail` with `|| true`: fzf exits 130 on Esc and on the `+abort` bindings;
  `|| true` absorbs that and any SIGPIPE in `--list`. Running `--list` directly with a
  missing folder fails loudly, but the main path checks the folder first.
- fzf placeholders: `'$self'` expands at launch to a quoted absolute path, and `{2}` is the
  last field, so it has no trailing tab. The listed paths contain no spaces or quotes
  (finding 6 removes those), so quoting cannot break; fzf's own quoting for fish was not
  tested. Verified: all 625 real rows have exactly two tab fields; whisper output folds
  whitespace, so new first lines cannot contain a tab.
- `--copy-text`: the sed strips `[HH:MM:SS] ` and an optional source label; `paste -sd' '`
  joins lines with spaces and `tr -d '\n'` drops the final newline (verified on a sample).
  It reads, and so downloads, the file, which is the intended explicit action.

Hermes: `"t": ["Transcript history", {"shell": ...}]` matches the documented form; the
terminal closes when the picker exits.
