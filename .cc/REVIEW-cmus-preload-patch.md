# Review: cmus patch to preload upcoming tracks

Reviewed 2026-11-08 against cmus 2.12.0 and 2.13.0 source, rclone 1.75.2 source, go-nfs 0.0.4 source, and the local rclone cache.

Each finding is labelled **Verified** (with the method) or **Inference**.

## Verdict

Do not build the patch yet.

1. The patch works. It is close to its claimed size, and a test gave 20 of 20 correct predictions.
2. Its reason for existing is wrong. Unpatched cmus can reveal the upcoming library tracks. A cursor probe gave 12 of 12 correct predictions on an unmodified build.
3. The proposal skips a cheaper fix. Each uncached track probably pays for up to two full SSH logins and a full-file MD5 on the server, before the first byte arrives. Three rclone settings remove that. Nobody has measured how much of the 3 to 7 s this is.

**Do this first:** change the rclone settings and measure again. Build preloading only if the delay is still too long. If you build it, use the unpatched probe, not the patch.

## Ranking

| Rank | Option | Cost | Why |
|---|---|---|---|
| 1 | Config-only tuning | About 15 minutes, reversible | Attacks the cost on every uncached track. Also helps manual skips, which preloading covers for two tracks only. Needs no order prediction. |
| 2 | Preload with no patch (cursor probe, or option B) | A few hours for the script and guards | Only if tuning is not enough. The probe keeps `:rand` in the library. B is exact, but it changes how you play music. |
| 3 | Do nothing | None | The delay is annoying, not a fault. |
| 4 | The patch | Patch is small; upkeep is ongoing | Correct, but replaces a working unpatched route with a personal build. |
| 5 | Option A (script-managed queue) | Script plus changed behaviour | The previous key does not return to queued songs. `:rand` order stops being what plays. |

**What would change this ranking**

- SSH login and MD5 turn out to be small (see "How to measure"). Then the time is in server disk or transfer. Tuning helps little, and preloading moves to rank 1. The patch still stays below the probe.
- You often leave view 2 or use marks. The probe gets less reliable, and B or the patch becomes more attractive.
- A later cmus adds a way to read play order. Then the probe is no longer needed.

## Q1. Can unpatched cmus reveal the upcoming tracks?

**The claim is false.**

**Why `save` returned the order it did. Verified by reading `lib.c:883-928`, `command_mode.c:191-213`.** All library `save` forms go through `do_lib_for_each`. That function walks the file hash table and runs `qsort` with the `lib_sort` keys. It never reads `lib_editable`, so `:rand` cannot affect it. On the test build, `save -l -`, `save -L -` and `save -` were identical and filename-sorted after `:rand` (tags were identical in the test corpus).

**Route 1: cursor probe. Verified: 12 of 12 next tracks predicted, unmodified 2.12.0, 4,300 synthetic files, `:rand` applied.**

```
cmus-remote -C "win-sel-cur" "win-down" "echo {}" "win-sel-cur"
```

`echo {}` writes the selected file to the remote client (`info_msg` at `ui_curses.c:1536` writes to `client_fd`). `win-down` walks the same list `lib_goto_next` walks. Repeat `win-down` and `echo {}` for a second track. Limits:

- It needs view 2 to be active. Your `rc` sets `start_view=sorted`. No status field shows the current view (Inference, from reading `cmd_status`). If you are in another view, the script preloads wrong tracks. That wastes data but breaks nothing.
- Marks break it, because `echo {}` then returns the first marked track (`_editable_for_each_sel`). Verified by reading.
- At the end of the list `win-down` stays put, so the script must detect that and use `win-top`.
- It ignores `aaa_mode`. Yours is `all`, so this does not matter now.
- It moves the cursor. Your `follow=true` already moves it on each track change. Run the probe on track changes only, so pause does not move it.

**Route 2: `mark` then `run` after each `:rand`. Verified: the 4,300-entry output matched the patched order exactly.** `:run` passes the marked tracks to a program in list order. Costs: needs `confirm_run=false`, blocks the cmus main loop while the program runs (`spawn` with `do_wait=1`), and starts a re-check of all 4,300 files over the mount (`cmus_update_tis`). The list is stale after the next `:rand`, so it must be wrapped in a key binding.

**Route 3: `set lib_sort=filename`. Verified: 10 of 10 predicted with plain `save -l -`.** Every file name I saw is a random UUID, so filename order is effectively a shuffle. It survives restarts, and it needs no cursor. It is one fixed order: there is no reshuffle.

**Also checked:** the `-Q` status, `format_print` and `status_display_program` carry no next-track data (Verified by reading `server.c`, `ui_curses.c`).

## Q2. The patch

**Size. Verified by `git diff`.** 21 changed code lines (17 added, 4 replaced) and 5 doc lines. "About 15" is close.

**Order correctness. Verified: 20 of 20 predicted on a patched 2.12.0 with 4,300 files.** The `play_sorted`, `shuffle=off` branch of `lib_goto_next` is `simple_list_get_next(&lib_editable.head, lib_cur_track, aaa_mode_filter, true)`, so `lib_editable` is the true list. These cases differ from a plain "next line in the file" (all Verified by reading `lib.c`, `cmus.c`, `track.c`):

| Case | Effect | Script must |
|---|---|---|
| Queue not empty | `play_queue_remove()` runs first | Check `save -q -` first |
| `aaa_mode` not `all` | Filter skips rows | Stop, or use the upcoming-list variant below |
| `repeat=true` at end of list | Wraps to the top | Wrap |
| `repeat=false` at end | Stops | Stop |
| `repeat_current=true` | Same track again | Skip |
| `play_library=false` | Playlist plays, not library | Check `-Q` |
| `continue_album` | Only matters when false; yours is true | Nothing |
| Filters | `lib_editable` holds only visible tracks, which is correct | Nothing |
| New tracks added while playing | Inserted, list stays valid | Re-read each time |

**Order is fragile. Verified by reading `lib.c`, `ui_curses.c:2532`.** `:rand` is lost when cmus restarts, because `lib.pl` is written through the sorted path. A filter change that re-adds tracks, or `set lib_sort`, also resets it. The patch reports the real order in all these cases, but the order you wanted may be gone.

**Current track to file path. Verified by reading `hash_insert`.** Duplicate file names are refused, so the path is unique and maps reliably.

**Remote `save` to stdout. Verified.** `save -o -` through `cmus-remote` returned all 4,300 lines.

**Load. Verified, measured over 30 runs.** `save -o -` took 17 ms median (`save -l -` took 147 ms, because of `qsort`). Your real paths are shorter than the test paths. This is no concern at one call per track change.

**A better patch shape (not compiled).** Printing only the next few tracks would remove the search and the wrap logic, and would respect `aaa_mode`. It would use `simple_list_get_next` from `lib_cur_track` in a small loop, with a guard for `lib_cur_track == NULL`.

**Draft patch. Verified: compiles on 2.12.0 and works as described.** On 2.13.0, `git apply --check` fails on `command_mode.h` because a nearby line changed. `git apply -3` applies it cleanly and it compiles. Behaviour was not retested on 2.13.0.

```diff
--- a/lib.c
+++ b/lib.c
@@ -926,3 +926,10 @@ int lib_for_each_filtered(...)
 	return do_lib_for_each(cb, data, 1);
 }
+
+/* lib_editable order: the list play_sorted mode really walks */
+int lib_for_each_view_order(int (*cb)(void *data, struct track_info *ti),
+		void *data, void *opaque)
+{
+	return editable_for_each(&lib_editable, cb, data, 0);
+}
--- a/lib.h
+++ b/lib.h
@@ -128,6 +128,8 @@
 int lib_for_each_filtered(int (*cb)(void *data, struct track_info *ti),
 		void *data, void *opaque);
+int lib_for_each_view_order(int (*cb)(void *data, struct track_info *ti),
+		void *data, void *opaque);
--- a/command_mode.h
+++ b/command_mode.h
@@ -72,7 +72,7 @@
-void view_save(int view, char *arg, int to_stdout, int filtered, int extended);
+void view_save(int view, char *arg, int to_stdout, int filtered, int extended, int ordered);
--- a/command_mode.c
+++ b/command_mode.c
@@ -188,12 +188,15 @@
-void view_save(int view, char *arg, int to_stdout, int filtered, int extended)
+void view_save(int view, char *arg, int to_stdout, int filtered, int extended, int ordered)
 {
 	char **dest;
 	save_ti_cb     save_ti         = extended ? cmus_save_ext         : cmus_save;
 	for_each_ti_cb lib_for_each_ti = filtered ? lib_for_each_filtered : lib_for_each;
 
+	if (ordered)
+		lib_for_each_ti = lib_for_each_view_order;
+
@@ -323,6 +326,7 @@ static int flag_to_view(int flag)
 	case 'l':
 	case 'L':
+	case 'o':
 		return TREE_VIEW;
@@ -400,7 +404,7 @@ static void cmd_save(char *arg)
-		f = parse_one_flag((const char **)&arg, "eLlpq");
+		f = parse_one_flag((const char **)&arg, "eLlopq");
@@ -409,7 +413,7 @@ static void cmd_save(char *arg)
-	view_save(flag_to_view(flag), arg, to_stdout, flag == 'L', extended);
+	view_save(flag_to_view(flag), arg, to_stdout, flag == 'L', extended, flag == 'o');
```

Use as `cmus-remote -C "save -o -"`. The man page text is in `Doc/cmus.txt` (5 lines, not shown).

## Q3. Build and upkeep

- **Build time. Verified.** About 3 s with `make -j8`.
- **A hand build does not pick up Homebrew cleanly on this machine. Verified.** `scripts/checks.sh:139` adds `-I/opt/local/include -L/opt/local/lib` whenever `/opt/local/lib` exists, and MacPorts is installed here. With a Homebrew-only `PATH`, the binary still linked `/opt/local/lib/libncurses.6.dylib` and `libiconv`. Homebrew's own build wrapper probably strips those paths (Inference, not tested, because installing was out of scope).
- **`ffmpeg.so`. Verified.** The 2.12.0 hand build skipped it (`CONFIG_FFMPEG = n`). The 2.13.0 hand build produced it; that release added a libavutil check (commit `66ee9c3`). For `.m4a` the `mp4` plugin is what plays (priority 50, against 30 for ffmpeg), so playback is not affected. Only the fallback is lost.
- **Plugins. Verified.** `mp4.so` linked Homebrew `mp4v2` and `faad2`; `coreaudio.so` and `ao.so` built.
- **Homebrew's formula. Verified.** The installed 2.12.0_3 formula has no patches of its own. 2.13.0 moves from `ffmpeg@7` to `ffmpeg`.
- **Ways to carry the patch. Verified from docs.brew.sh.**
  - `brew edit` requires `HOMEBREW_NO_INSTALL_FROM_API=1` set before every `brew install` and `brew update`, and a full core tap.
  - A personal tap cannot install a same-named formula beside core. Use a renamed formula such as `cmus-preload` with `conflicts_with "cmus"` and `patch :DATA`.
  - Either way you lose the bottle. You currently use one (`poured_from_bottle: true`). Rebuild is likely after dependency library changes (Inference).
- **"About an hour." Inference.** Fair for the patch and a first build. Not for the patch, the tap, the trigger script and the guards in Q5 together.
- **Upstream. Verified by `gh search` on cmus/cmus** (keyword search only, so absence is not proof). I found no issue or PR for exposing play order. The nearest is #272, on remote-filesystem buffering, where a maintainer states that cmus does not preload the next track.

## Q4. Does preloading fix the delay? Is there something cheaper?

### What happens on an uncached track

1. **Fingerprint runs a full-file MD5 on the server. Verified.** The default fingerprint includes the hash. `item._checkObject` calls `fs.Fingerprint`, which calls `o.Hash`, which runs `md5 -r <file>` remotely (`backend/sftp/sftp.go:2371`, `fs/fingerprint.go`). All 69 cache entries have a three-field fingerprint with a 32-character MD5, so this really ran for each one.
2. **Each remote command is a new SSH login. Verified by reading `ssh_external.go`.** With `ssh =` set, `NewSession` starts a new `ssh` process (log text: "creating additional session"). There is no multiplexing.
3. **The connection pool is empty by the next track. Verified from code; timing is Inference.** `idle_timeout` defaults to 60 s. A 4 MB file downloads in seconds, then nothing happens for minutes. Your `ssh` line has no `ControlMaster`.

So the worst case per uncached track is: login for the SFTP connection, a second login for `md5`, the server reads and hashes the whole file, then the actual open and read. This fits a floor of about 3 s. **The size of each part is not measured** (I could not connect to the server).

### What else I found

- **Hourly directory re-read. Verified from `vfs/dir.go`.** With `--dir-cache-time 1h`, the first lookup after expiry re-lists all 4,300 entries while holding the directory lock. New objects also lose their stored MD5, so even cached tracks then pay a login and MD5 once more. This is an occasional spike.
- **The `rclone cat` test was not a clean baseline. Verified from `fs/walk/walk.go`, `cmd/cmd.go`.** `rclone cat remote:dir/file` lists the whole parent directory unless `--no-traverse` is given.
- **The 64 KB test understates the real cost. Partly verified.** 29 of 30 sampled cached files are laid out `ftyp free mdat moov`, with the index at the end (the 30th returned zeros at offset 0). The `mp4` plugin (`MP4Read`) must read that index before any audio. One partial cache entry holds the first 2 MB and the last 96 KB, which shows the tail is read early. How long the tail read waits is **not resolved**: the downloader code suggests it reuses the sequential download, and that one entry suggests it does not.
- **cmus has no read-ahead of its own. Verified from `player.c:807-848`.** The next file opens only when the audio buffer is empty, so the delay is heard on natural track changes too.

### Would preloading work?

Yes, if the prediction is right. All of this is Verified from code unless marked:

- Reading a whole file through the mount fills the cache; 68 of 69 played entries are complete.
- Read to the end. A partial read stops the download about 5 s after close (`vfs_handle_caching`).
- A preload still running helps the player. Both share one cache item and its downloader.
- The macOS NFS page cache can only make the second read faster (Inference).
- The 2 GB cache holds about 500 tracks at the 3.98 MB median, so eviction is no concern (Inference on eviction order).
- The preload pays for the MD5 and logins as well, in the background. That costs server time on one core while the current track may still be downloading.
- It covers the next two tracks only. A third quick skip is uncached.

### Cheaper changes

In `services/music-mount/script.sh`:

```
--vfs-fast-fingerprint       # no more MD5 per file
--sftp-idle-timeout 0        # keep the connection
--dir-cache-time 168h        # no hourly re-list
```

In the `ssh =` line of `rclone.conf`, add `-o ServerAliveInterval=15 -o ServerAliveCountMax=3`. This is required with `--sftp-idle-timeout 0`. External SSH sends no keepalives (`SendKeepAlive` is empty), so a dropped connection could otherwise hang the next track.

Costs: the 69 cached entries re-download once, because the fingerprint format changes (Verified). After adding music you must restart the service to see it, because of the longer directory cache.

| Flag | Useful here? |
|---|---|
| `--vfs-read-ahead` | No. Files are smaller than the 16 MiB buffer. |
| `--buffer-size` | No effect on first byte. |
| `--no-modtime` | No. Modtime comes from the listing. |
| `--sftp-chunk-size`, `--sftp-concurrency` | Transfer speed only, not the wait. Try later if needed. |
| `ControlMaster` | Not needed once the two flags above are set. |
| Move `moov` to the start of each file | Rewrites the only independent copy of the library. Not worth it. |

### How to measure

Run these on the server's real path, on tracks not yet cached:

1. `time ssh <host> true`, twice. This is the login cost.
2. `time ssh <host> 'md5 -r <file>'`. Login plus MD5.
3. `rclone cat --no-traverse` instead of plain `rclone cat`.
4. Time a **whole-file** read, or time the track start in cmus. Change one setting at a time.
5. For detail, run once with `--log-level DEBUG` and look for `Running remote command: md5` and `creating additional session`.

## Q5. Timing hazards

**Correction to the brief. Verified from `player.c:1226-1300`.** A seek during playback does not fire the status program. It fires only for a seek from stopped. It does fire on pause and resume, file change and metadata change (`ui_curses.c:1982`).

**Good news. Verified from `spawn.c`.** cmus does not wait for the status program (double fork, `do_wait=0`). A script calling `cmus-remote` cannot deadlock it.

Guards needed:

1. **Act only on a new file.** Compare against a state file. Require `status playing`.
2. **Debounce.** Wait 3 to 5 s, then re-read `-Q`. Exit if the track changed. This handles fast skipping and lets the current track finish its download on the one-core server first.
3. **One preloader at a time.** Use a `mkdir` lock or `shlock` (`flock` is not installed). Kill the previous run by process group.
4. **Run it separately and in the background.** Do not delay the existing Hammerspoon message. Use a separate script, because fish cannot background a function.
5. **Read one file at a time, to the end, with a deadline** (`timeout`). A dead mount otherwise hangs forever.
6. **Check the mode first:** `play_library=true`, `repeat_current=false`, queue empty.
7. **Probe only:** run on track change only. Wrap at the end of the list.

## Other notes

- **Option A. Verified from `cmus.c`.** `cmus_prev` goes to `lib_goto_prev`. Queue tracks are not recorded, so the previous key does not return to them. `:tqueue N` exists and would avoid custom random selection, but not repeats.
- **Option B. Verified from `pl.c`.** `save -p -` exports the *visible* playlist (`pl_visible`), so browsing another playlist makes the script read the wrong list. Playlist order is saved in list order, so it survives restarts, unlike `:rand`. Your picker's `cmus-remote --clear` clears the playlist in view, so a dedicated playlist needs care.
- **`~/.config/cmus/lib.pl` was empty during this review.** cmus writes it on exit. A crash of this session would lose the library list, and you would need to add the folder again.

## Method and limits

- Tests ran on scratch builds with an isolated `CMUS_HOME` and socket, using 4,300 hard links to one silent 1 s file, in the stopped state with `-n`. No audio played and no real tracks were used.
- Your cmus received only read-only queries: `-Q` and `set lib_sort?`. It moved from playing to paused during the review; no command of mine was sent to it that could cause that.
- I did not connect to the server, change the mount, or install anything. Every server-side time above is an estimate or marked unmeasured.
