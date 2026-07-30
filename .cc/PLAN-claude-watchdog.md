# PLAN: `claude-watchdog` — a launchd backstop for runaway headless `claude`

Status: **design only**. No service code, plist, or script written. Nothing committed.
Author: investigation of 2026-07-29 against the live machine.

Every number below is tagged with where it came from: `[measured]` = I ran the command on
this machine today, `[incident]` = established fact from the 2026-07-28 event, `[assumption]`
= a guess that phase 1 must confirm.

---

## 1. The incident, and what already defends against it

On 2026-07-28 ~16:44 a headless `claude` wedged: 2.76 GB real / 8.65 GB allocated, ~98% CPU,
2 threads, stdin on `/dev/null`, no controlling tty, no transcript, killed by hand. `[incident]`

**Flag on the brief's framing.** The brief says to "assume an unpredictable, rare startup hang
rather than a known trigger". That is too pessimistic. `bin/claude-p` — written **2026-07-28
19:00**, ~2h after the incident — documents the trigger in its own header:

> `bin/claude-p:8-11` — "A retired or unavailable `--model` makes claude print an error and
> then spin: ~98% CPU, RAM climbing past 2.7GB, never exiting. Nothing upstream notices,
> because a departed pipe reader does not kill the writer."

So the signature is known and named, it is already closed in-band for every caller that goes
through `claude-p` (`timeout -k`, child in its own process group), and `bin/tab-organize`
(`CLAUDE_TIMEOUT`, `bin/tab-organize:257` even notes "claude spawns helpers of its own") and
`bin/ai-commit-msg` (SDK deadline, comment cites "seen 2026-07-28: ~98% CPU") carry their own
deadlines. `[measured]`

What is *not* reproducible is the manifestation. I re-ran the retired-model probe today: it
exited in ~1.25 s, no wedge. `[measured]` So: known trigger, intermittent expression.

That changes what the watchdog is **for**. It is not the primary defence — a per-spawner
deadline is, and it is strictly better because it knows the caller's intent. The watchdog is
the backstop for the three cases a deadline cannot reach:

| Case | Why in-band deadlines miss it |
|---|---|
| Orphans (ppid 1) | the deadline's owner is already dead |
| Un-audited / future spawners | nobody remembered to add a deadline |
| Third-party SDK children | the spawn is inside `claude_agent_sdk`, not our code |

**Recommendation: build it, but bill it as a backstop, and fix the one un-deadlined spawner I
found in-band rather than trying to cover it from outside** —
`fish/functions/_claude_release_notes.fish:26` pipes into a raw `claude -p` with no timeout.
`[measured]` The watchdog structurally *cannot* catch that one (§6: it inherits the calling
shell's tty).

---

## 2. Goals

1. Detect a headless `claude` that is burning CPU and growing RSS far outside the measured
   healthy envelope, sustained over minutes.
2. Capture, before acting, everything that reconstructing the 2026-07-28 incident took by
   hand (an Activity Monitor screenshot plus four transcripts) — into one file.
3. Kill it, gently then firmly, without ever touching an interactive session.
4. Tell me it happened.
5. Cost near nothing when nothing is wrong. Full sample is 48 ms. `[measured]`

## 3. Non-goals

- **Not a replacement for `claude-p` / per-caller deadlines.** Those stay; they act in
  seconds, the watchdog in minutes.
- **Not a memory-pressure manager.** It does not kill the largest claude, only ones outside
  the envelope. Ten healthy sessions at 400 MB each is 4 GB and is none of its business.
- **Not covering tty-attached processes at all** — see §6. A wedged `claude -p` typed at my
  own prompt is out of scope by construction.
- **Not covering non-`claude` runaways.** No generic process reaper.
- **No self-healing / restart.** It kills; it does not relaunch anything.
- **Not root.** Everything it needs works same-uid. `[measured]`

---

## 4. Measured baseline (the whole design rests on this table)

All from `ps -axo …` on 2026-07-29 unless marked. `ps` RSS is in KB.

| What | RSS | CPU | Threads | tty | Source |
|---|---|---|---|---|---|
| Interactive sessions, 5 live | 261 / 299 / 372 / 419 / 508 MB | 0.1–11% | 25 | `ttys00N` | `[measured]` |
| Interactive sessions, 10 live | 140–575 MB | — | ~25 | — | `[incident]` baseline |
| Headless, healthy, t≈4 s | 387, 391 MB | ~0% | — | `??` | `[measured]` |
| Headless, healthy, idle at 1:48 | 390–408 MB | 0.0–0.3% | **11** | `??` | `[measured]` |
| Headless, healthy, t=0.25 s | **7.6 MB** | 0.0% | **2** | `??` | `[measured]` |
| Headless, healthy, t=0.5–0.75 s | 344–380 MB | **50.9 / 52.8%** | 15 | `??` | `[measured]` |
| **The runaway** | **2760 MB** | **~98%** | **2** | `??` | `[incident]` |

Highest healthy figure anywhere: **575 MB**. Runaway: **2760 MB**. Headroom **4.8×**.

### Three things this table kills

**(a) "2 threads" is not a wedge signature.** A perfectly healthy headless `claude` shows
2 threads at t=0.25 s, 15 at t=0.5 s, and settles to 11 when idle — not the ~25 of an
interactive session. `[measured]` Thread count is usable only as a *corroborating* field
alongside elapsed ≥ 60 s (2 threads at 1+ minute genuinely means "died before the thread pool
came up"). It must never be a primary threshold; on its own it false-positives on every
claude's first half-second.

**(b) A healthy headless claude can be long-lived and idle.** I watched one sit at ~400 MB,
11 threads, ~0% CPU for 1:48+ before exiting. `[measured]` Elapsed time alone can never
trigger anything.

**(c) `ps` RSS and the 2.76 GB figure are different metrics.** For pid 64793: `ps` RSS
419 MB, `sample`'s "Physical footprint" 327.5 MB — `ps` RSS reads **1.28× higher**.
`[measured]` The 2.76 GB is an Activity Monitor (footprint) number, so the runaway's `ps` RSS
was likely nearer **3.5 GB**. Any threshold expressed in `ps` RSS is therefore calibrated
against a *different scale* than the incident figure. This is the single strongest argument
for §12's log-only phase: one data point on the wrong scale is not a distribution.

---

## 5. What `ps` can and cannot give us (macOS, BSD, no `/proc`)

| Need | Mechanism | Cost | Notes |
|---|---|---|---|
| pid, ppid, **pgid**, sess | `ps -axo pid,ppid,pgid,sess` | — | all present `[measured]` |
| RSS, VSZ | `rss`, `vsz` | — | KB; see §4(c) |
| Executable identity | **`ucomm`** | — | **key finding, below** |
| argv[0] / label | `comm`, or `args` with `-ww` | — | see below |
| Cumulative CPU time | `time` | — | format `MMM:SS.ss`, minutes **unbounded** (saw `2425:54.43`) `[measured]` |
| Instantaneous %CPU | `pcpu` | — | **do not trust**, see below |
| Elapsed | `etime` | — | three forms: `MM:SS`, `HH:MM:SS`, `DD-HH:MM:SS` `[measured]`. **No `etimes`** — that keyword does not exist here `[measured]` |
| Thread count | `ps -M -p PID \| tail -n +2 \| wc -l` | 5 ms `[measured]` | no `thcount`/`nlwp` keyword on macOS `[measured]` |
| Environment | `ps -Eww -p PID` | — | works same-uid `[measured]`; **must be redacted**, §9 |
| Open files, cwd | `lsof -p PID` | 121 ms `[measured]` | per-suspect only, never per-sample |
| Where it is spinning | `sample PID 2 -f out` | 2.4 s, 163 KB → 30 KB gz `[measured]` | no sudo; also prints Physical footprint + **peak** |
| Full sample sweep | `ps -axo pid,ppid,rss,pcpu,time,etime,tty,ucomm,comm` | **48 ms** `[measured]` | |

### `ucomm` vs `comm` — the identity/label split

`ps -o ucomm` is the **executable** basename (kernel `p_comm`, ≤16 chars) and is **not**
affected by `setproctitle` or `argv[0]`. `ps -o comm` is **`argv[0]`**, which is where the
proc-label lands.

Control experiment: `bash -c 'exec -a WEIRDNAME_TEST sleep 45'` →
`COMM=WEIRDNAME_TEST`, `UCOMM=sleep`. `[measured]`
Live labelled session pid 81826 → `COMM=claude [Polymnia 19:13:41]`, `UCOMM=2.1.220`.
`[measured]`

This is exactly the pair the watchdog needs: **`ucomm` answers "is this claude", `comm`/`args`
answers "is it labelled"**, and the two cannot contaminate each other.

### `pcpu` is a decayed estimate, not an interval average

Two reads 3 s apart on pid 18056 gave `pcpu` 2.9% then 2.2%, while `time` went
`77:20.99 → 77:21.30` — 0.31 s CPU over ~3.1 s wall, i.e. **~10%** actual. `[measured]`
**Compute %CPU from `time` deltas across samples**, never from `pcpu`. Log `pcpu` anyway, for
correlation with what Activity Monitor would have shown.

---

## 6. Classification — and the brief's discriminator is wrong

### 6.1 "Is it claude?"

`ucomm` ∈ a set derived at each run, not hardcoded:

- `basename "$(readlink ~/.local/bin/claude)"` → today **`2.1.220`**.
  `~/.local/bin/claude` is a **direct symlink** to `~/.local/share/claude/versions/2.1.220`
  — there is no shim script. `[measured]` **Hardcoding `2.1.220` would silently stop working
  at the next update; derive it.**
- the literal `claude`, for the SDK's bundled copy: a separate **192 MB** Mach-O at
  `…/site-packages/claude_agent_sdk/_bundled/claude`. `[measured]` Present in the inari venv,
  the spirit-read/tarot-read/health-read uv environments, `~/spotify/.venv`, and 11 uv
  archive caches. `[measured]`

`bin/claude-p`, `bin/claude-batch`, `bin/claude-batch-worker` are shell scripts, so their
`ucomm` is `bash`/`fish` — no collision. `[measured]`

Before any signal is sent, re-confirm identity from `lsof -p PID -a -d txt` (the `txt` row is
the real executable path). `[measured]` `ucomm` is a 16-char truncation and is not
authoritative enough to kill on.

Also: **`claude` spawns `claude` children.** Measured pid 23300 with ppid 23247, both
`ucomm=2.1.220`. `[measured]` `bin/tab-organize:257` independently documents this. Consequences
in §8.4.

Skip any row whose `comm` is parenthesised — e.g. the `(2.1.220)` I captured for pid 23300.
`[measured]` That is a zombie / mid-`exec` state with unreadable argv; it is not a candidate.

### 6.2 "Is it interactive?" — use **tty**, not the label

The brief proposes the proc-label as the discriminator. **It is not safe as the primary
guard, for two independent reasons:**

1. **An interactive session can lack the label.** `claude` is not shadowed by any fish
   function or alias — the only binding is `abbr -a cc my-claude-code-wrapper`
   (`fish/conf.d/abbr.fish:2`), and there is no `fish/functions/claude.fish`. `[measured]`
   Typing `claude` at the prompt therefore starts a **completely unlabelled interactive
   session**. If the label were the guard, that session would be a kill candidate.
2. **A headless invocation can carry the label.** In
   `my-claude-code-wrapper.fish`, `proc-label "claude [$label]" claude --verbose $pass_argv`
   runs **unconditionally**. The `-p`/`--print` check above it sets `skip_extras`, which gates
   only the session-review and open-session registry — *not* the labelling. `[measured]`
   So `cc -p '…'` is a labelled headless process.

The label's real meaning is **"went through the fish wrapper"**, not "interactive".

The **controlling tty** is the honest signal, and it matches the incident directly ("no
controlling tty", "stdin on `/dev/null`"). Measured today: all 5 labelled interactive sessions
had `ttys004/006/007/011/015`; every headless child had `??`. `[measured]`

**Classification rules, in order:**

| # | Rule | Effect |
|---|---|---|
| G1 | `tty != "??"` | **exempt, unconditionally.** Primary guard. |
| G2 | `comm` matches `^claude \[.*\]$` (the proc-label shape) | **exempt.** Secondary guard, catches a wrapper session that somehow lost its tty. |
| G3 | `ucomm` not in the derived claude set | not a candidate |
| G4 | `comm` parenthesised | skip (zombie/mid-exec) |
| C1 | else → **headless candidate** |
| C2 | headless candidate **and** `ppid == 1` → **orphan candidate** (§7.3) |

### 6.3 Failure cases of this classification

| Case | Class | Consequence |
|---|---|---|
| Bare `claude` at a prompt | tty → exempt (G1) | correct |
| `cc -p '…'` at a prompt | tty **and** label → exempt | correct, doubly |
| `echo x \| claude -p …` at a prompt (e.g. `_claude_release_notes.fish:26`) | inherits the shell's tty → **exempt** | **false negative, accepted.** Fix in-band. |
| Bash-tool child (the incident) | `??`, bare argv → candidate | **the target case** |
| SDK child under a launchd service | `??`, bare argv → candidate | correct |
| `cc-session-review` after wrapper exit | `??`, ppid 1 → **orphan** | **legitimate orphan — see §7.3** |
| claude-spawned claude helper | `??`, bare argv → candidate | correct, but tiny/short-lived; never reaches thresholds |
| tmux/screen pane | has a pty → exempt | correct |
| A future wrapper that stops proc-labelling | still tty-guarded | G1 degrades safely; the brief's design would not |

---

## 7. Detection rules

### 7.1 Sampling shape

**Not a resident daemon.** `StartInterval 60` + a script that lives ~50 s and exits. A process
with a 50-second lifetime cannot leak and cannot wedge unnoticed (§13.2). launchd will not
start a second copy while one is running.

Inside one run: **6 samples at 8 s intervals** (t = 0 … 40 s), giving 5 CPU-time deltas.
Cost: 6 × 48 ms ≈ 0.3 s of `ps` per minute. `[measured]`

A candidate must be over threshold on **every sample in the window** — that is the brief's
"sustained, not instantaneous", satisfied *within* one run, so detection latency is bounded at
~100 s from onset rather than the ~5 min that 5 × 60 s cross-run sampling would cost. Given
the runaway reached 2.76 GB in about a minute `[incident]`, minutes of latency is memory the
machine does not have to give.

A small state file carries **strike counts** and **already-acted pids** across runs (§13.3).

### 7.2 Headless thresholds

All four must hold, on every sample in the window:

| Field | Phase-2 candidate | Where the number comes from |
|---|---|---|
| `age` | ≥ **90 s** | runaway was already >60 s `[incident]`; healthy startup burst is <2 s `[measured]`, so 90 s is generous insurance |
| `rss` | ≥ **1400 MB** | 2.4× the highest healthy observation (575 MB `[incident]`), ~0.5× the runaway on the Activity-Monitor scale and ~0.4× on the `ps` scale (§4c). Formula to re-derive in phase 2: `p100(healthy headless RSS) × 3`, floored at 1 GB |
| `cpu` (from `time` deltas) | ≥ **70%** | runaway ~98% `[incident]`; healthy peak over a 40 s window `[assumption]` — highest I saw was a 50.9% *sub-second* startup burst `[measured]`, never sustained. **Phase 1 must confirm no healthy headless run sustains 70% over 40 s.** |
| `rss` trend | non-decreasing across the window | "still climbing after 1+ minute" `[incident]`; distinguishes a wedge from a legitimately heavy one-shot |

Recorded but **not** thresholded: thread count (§4a), `pcpu`, `vsz`.

### 7.3 Orphan thresholds — and a real false-positive path

`ppid == 1`: on macOS the child reparents to launchd when its spawner dies, so nothing can
ever reap it. Lower bar is right in principle. But the brief's "orphans get their own, lower
bar" needs a floor, because **this machine produces legitimate orphaned headless claudes as
routine behaviour**:

`my-claude-code-wrapper.fish` launches the post-session review as
`fish -c "cc-session-review '$post_latest'" &>/dev/null & disown`, and `cc-session-review.fish:79`
runs `CLAUDE_P_TIMEOUT=300 claude-p …`. `[measured]` When the wrapper's fish exits, that claude
is `tty=??`, `ppid=1`, and **legitimately alive for up to 305 s** (300 + `CLAUDE_P_KILL_AFTER`
5). The same shape applies to the disowned `_ccs_backup_session`. The largest
`CLAUDE_P_TIMEOUT` configured anywhere is **300** (`cc-session-review.fish:79`,
`claude-batch-worker:28`, `ai-chunk-files.fish:44`). `[measured]`

| Field | Phase-2 candidate | Reasoning |
|---|---|---|
| `age` | ≥ **420 s** | 305 s worst legitimate lifetime `[measured]` + ~40% margin for a future raise |
| `rss` | ≥ **900 MB** | ~2.2× healthy headless (~408 MB `[measured]`), 1.6× the 575 MB max healthy |
| `cpu` | ≥ **50%** | lower than headless: nobody is coming, so a *spinning* orphan is unambiguous |
| window | all samples | same as headless |

**An idle orphan is deliberately not killed.** RSS ~400 MB, ~0% CPU, ppid 1 is what a
disowned review looks like, and could equally be something I `nohup`'d on purpose. Phase 2
**logs and notifies** for `ppid==1 && age > 30 min && cpu < 5%` and stops there. See §15 Q3.

---

## 8. Action ladder

### 8.1 The ladder

| Step | Action | Wait |
|---|---|---|
| 0 | Append one line per sample to the service log | — |
| 1 | Thresholds met → write the forensic bundle (§9) | — |
| 2 | `terminal-notifier` alert, grouped on the pid | — |
| 3 | `SIGTERM` | grace **10 s**, re-check |
| 4 | still alive → `SIGKILL` | 2 s, re-check |
| 5 | still alive after SIGKILL → log `UNKILLABLE`, notify, add pid to the never-retry set | — |

`SIGTERM` first because a claude that is merely slow may flush and exit cleanly, leaving a
transcript. The 10 s grace is `[assumption]` — the incident left no transcript at all, so
there is no evidence either way about whether a wedged claude can respond to `SIGTERM`.
Phase 2 will produce that evidence, since the bundle records which signal worked.

### 8.2 What is authorised per phase

| Phase | Steps authorised |
|---|---|
| 1 — observe | 0 only. **No bundle, no notify, no signal.** |
| 2 — forensics | 0, 1, 2. Bundle + notify. **No signal.** |
| 3 — enforce, orphans only | 0–5, but candidacy restricted to `ppid == 1` |
| 4 — enforce, all headless | 0–5 |

Hard-coded as a single `WATCHDOG_PHASE` value (§10), so advancing is a one-line, reversible
edit — and so phase 1 physically cannot kill anything.

### 8.3 Notification channel

**`terminal-notifier`** (`/opt/homebrew/bin/terminal-notifier` `[measured]`). This is the
established pattern here, and `bin/ytdl:210-212` states the reason in a comment: "reliable
from background/detached processes, unlike `osascript display notification`". `[measured]`
Group on the pid, as `ytdl` groups on the video id, so repeat notifications for one incident
collapse into one banner.

Rejected: **osascript** (documented as unreliable from detached processes, above);
**Telegram/inari** — there is no shell-callable send path in dotfiles. The only
`api.telegram.org` hit is a *comment* in `bin/service:58` about log noise. `[measured]`
Building one for this is out of scope; **hermes** has no notification facility `[measured]`.
Guard the call with an existence check and continue on failure, as `ytdl:224-226` does — a
missing notifier must never abort the kill.

### 8.4 Which pid(s) to signal

`claude` spawns `claude` children (§6.1). Signalling only the pid we hold can orphan a helper
— `bin/tab-organize:257` was written after learning that. Rule:

- If `pgid == pid`, the candidate leads its own group → signal the **group** (`kill -TERM -PGID`).
  GNU `timeout` (9.3, `/opt/homebrew/bin/timeout` `[measured]`) runs its child in a new process
  group and signals the group — which `bin/claude-p:12-13` relies on — so a `claude-p`-spawned
  candidate should satisfy this. `[assumption]` — I did not capture `pgid` on a live
  `timeout`-spawned claude. **Phase 1 records `pgid` and `sess` in every sample so this is
  confirmed from real data before phase 3.**
- Otherwise, signal the pid, then each claude descendant found by a ppid walk. **Never** signal
  the group, since the group may contain the spawner and its siblings.

---

## 9. Forensic bundle

One directory per incident:
`~/.local/state/claude-watchdog/incidents/<YYYY-MM-DD>T<HHMMSS>-pid<PID>/`

`~/.local/state` because `XDG_STATE_HOME` is `~/.local/state` (`fish/conf.d/00_xdg.fish`) and
these are recoverable state, not config or cache. Explicitly **not** `~/Cloud` — CLAUDE.md
records that as a ProtonDrive symlink, already a footgun for the ccs transcript cache.

| File | Contents | Cost |
|---|---|---|
| `summary.txt` | verdict, thresholds in force, phase, which rule fired, which signal worked | — |
| `samples.tsv` | one row per sample: `t rss vsz pcpu cputime cpu_pct threads age pgid sess stat` — **the RSS/CPU curve** the brief asked for | in-hand |
| `proc.txt` | `ps -o pid,ppid,pgid,sess,stat,tty,ucomm,args -ww -p PID` | — |
| `ancestry.txt` | ppid walk to pid 1, argv of each ancestor. **This is where the owning session appears**: the Bash-tool shell carries `export CLAUDE_SESSION_ID=<uuid>` literally in its argv — measured on pid 8807, `ppid=64793` = the owning claude session `[measured]` | — |
| `env.txt` | `ps -Eww -p PID`, **redacted** (below) | — |
| `openfiles.txt` | `lsof -p PID` — the `cwd` row and any `/private/tmp/claude-501/<slug>/<session-id>/tasks/*.output` row. That fd is what traced the owner on 2026-07-28 `[incident]`, and is the **only** owner evidence left once ancestry is gone (ppid 1) | 121 ms `[measured]` |
| `exe.txt` | `lsof -p PID -a -d txt` — authoritative executable path (§6.1) | — |
| `sample.txt.gz` | `sample PID 2` — **per-thread call graph** (where it is spinning), plus Physical footprint and **peak** footprint | 2.4 s, **30 KB gz** `[measured]` |
| `system.txt` | `vm_stat`, load average, count of all claude processes and their RSS | — |

`sample.txt.gz` is the highest-value addition over what I had by hand on 2026-07-28: for a
startup hang it names the function. Skip `vmmap` — `sample` already reports the footprint
figures, so it adds seconds for nothing.

**Redaction is mandatory, not hygiene.** These files are permanent, unencrypted and
unbacked-up — the same reasoning `bin/rotate-inari-log` gives for its own redaction. `ps -E`
dumps the whole environment. Rule: **drop the value of any variable whose *name* matches
`KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|AUTH`** (name-based, so it fails safe on shapes that do
not exist yet), and additionally apply `rotate-inari-log`'s shape rule
`([0-9]{6,12})(:|%3[Aa])[A-Za-z0-9_-]{30,}` to the whole file. Keep `CLAUDE_*`, `CCS_*`,
`PWD`, `TERM`, `TMPDIR`, `SSH_CONNECTION` in full — `CLAUDE_SESSION_ID` is the owner
identifier and `CCS_ENTRY_FILE` names the session's ccs entry (both observed in real claude
envs `[measured]`).

`chmod 700` the incidents dir and `600` the files, matching `rotate-inari-log`'s treatment of
`~/.log/services/archive` (which is `drwx------` on disk `[measured]`).

**Retention:** keep the **20 most recent** incident dirs; delete older ones at the start of
each run. At ~40 KB per bundle (30 KB of it the gzipped sample) that is under 1 MB total.
`[measured]` Rationale: if there are more than 20 incidents, the oldest is not the interesting
one — and a runaway loop must not be able to fill the disk while I sleep.

---

## 10. Config surface

A single sourced file, `~/dotfiles/services/claude-watchdog/config.sh`, with every value
overridable from the environment — the pattern `rotate-inari-log` uses
(`THRESHOLD_MB="${INARI_LOG_ROTATE_MB:-26}"`) and `claude-p` uses
(`TIMEOUT=${CLAUDE_P_TIMEOUT:-180}`). `[measured]` Env overrides make a one-shot manual run
(`CW_PHASE=2 CW_RSS_MB=200 ./script.sh`) trivial, which is most of the testing story in §14.

| Variable | Default | Meaning |
|---|---|---|
| `CW_PHASE` | `1` | 1 log · 2 +bundle/notify · 3 orphans only · 4 all |
| `CW_SAMPLES` | `6` | samples per run |
| `CW_SAMPLE_INTERVAL` | `8` | seconds between samples |
| `CW_MIN_AGE` | `90` | headless minimum elapsed, seconds |
| `CW_RSS_MB` | `1400` | headless RSS threshold |
| `CW_CPU_PCT` | `70` | headless CPU threshold (from `time` deltas) |
| `CW_ORPHAN_MIN_AGE` | `420` | orphan minimum elapsed |
| `CW_ORPHAN_RSS_MB` | `900` | orphan RSS threshold |
| `CW_ORPHAN_CPU_PCT` | `50` | orphan CPU threshold |
| `CW_TERM_GRACE` | `10` | seconds between SIGTERM and SIGKILL |
| `CW_KEEP_INCIDENTS` | `20` | incident dirs retained |
| `CW_LOG_ROTATE_MB` | `20` | log rotation trigger |
| `CW_NOTIFY` | `1` | 0 disables `terminal-notifier` |
| `CW_DRY_RUN` | `0` | 1 = log the signal it *would* send, send nothing |
| `CW_EXTRA_UCOMM` | *(empty)* | additional executable basenames to treat as claude |
| `CW_EXEMPT_PIDS` | *(empty)* | manual never-touch list |

Phase-1 observations get recorded in the plan file itself, not scattered — the thresholds
above are candidates until §12's exit criteria are met.

---

## 11. File layout

Matching what `service create` actually scaffolds (`bin/service:349-421` `[measured]`) — a
plist, a `dotfiles-services-<short>.sh` one-liner calling `bin/service-wrapper`, and
`script.sh`:

| Path | Role |
|---|---|
| `services/claude-watchdog/org.pancia.claude-watchdog.plist` | `Label org.pancia.claude-watchdog`; `ProgramArguments` = the wrapper; `RunAtLoad true`; **`StartInterval 60`**; `StandardOutPath`/`StandardErrorPath` = `~/.log/services/claude-watchdog.log`. **No `KeepAlive`** — `service create`'s template sets it, and it is wrong here: this is a short-lived periodic job, and `KeepAlive true` would relaunch it in a tight loop. Add `Nice 5` and `LowPriorityIO true`; do **not** set `ProcessType Background`, which invites App Nap throttling of a timing-sensitive sampler. |
| `services/claude-watchdog/dotfiles-services-claude-watchdog.sh` | verbatim from the template: `~/dotfiles/bin/service-wrapper ~/dotfiles/services/claude-watchdog/ ./script.sh`. `service-wrapper` cds and pipes through `ts '[%Y-%m-%d %H:%M:%S]'`, which is what gives the log its parseable date prefix — and `rotate-inari-log` keys its archive naming off exactly that prefix. `[measured]` |
| `services/claude-watchdog/script.sh` | `#!/usr/bin/env bash`, `set -uo pipefail`, then `exec timeout -k 5 55 ~/dotfiles/bin/claude-watchdog`. Follows `ziplog/script.sh`'s `exec`-into-a-`bin`-script shape `[measured]`. The `timeout` is the watchdog's own watchdog (§13.2). Not `set -e`: a failed `lsof` on one candidate must not abandon the others. |
| `bin/claude-watchdog` | the actual logic; lives in `bin/` so it is runnable by hand, like `ziplog --yes` and `rotate-inari-log` |
| `services/claude-watchdog/config.sh` | §10 defaults |
| `bin/rotate-service-log` | **generalisation of `bin/rotate-inari-log`** — see §13.4 |
| `docs/claude-watchdog.md` | thresholds and their provenance, the phase ladder, how to read a bundle |

**Registration.** Do **not** run `service create` — it would scaffold a `KeepAlive`
while-true template that has to be undone. Write the three files by hand in the same shapes,
then `service start claude-watchdog`; `bin/service:203-217` hard-links
`services/<short>/<full>.plist` into `~/Library/LaunchAgents/` and runs `launchctl load` +
`launchctl start`. `[measured]` Note the **hard link**: after editing the plist, `service
restart` is required for launchd to re-read it. Verify with `service status` and
`service log claude-watchdog -q -p`.

CLAUDE.md's service table and the "Available Services" list need a row; that edit is
deferred — another agent holds CLAUDE.md right now.

---

## 12. Rollout phases and exit criteria

**Phase 1 — observe (7 days).** `CW_PHASE=1`. Log one line per sample for every headless
candidate, plus a run-summary line. Log at a deliberately low bar — RSS ≥ 500 MB **or**
cpu ≥ 40% — so the log builds a distribution rather than only recording extremes.
Also record `pgid`/`sess` for §8.4's open question.

*Advance when:* ≥ 7 days elapsed; ≥ 50 distinct headless claude processes observed; the
observed healthy `ps`-RSS p100 is known and `CW_RSS_MB` re-derived as `p100 × 3` (floor 1 GB);
**zero** healthy process sustained ≥ `CW_CPU_PCT` across a full 40 s window; and the legitimate
`cc-session-review` orphans show up in the log with the lifetimes §7.3 predicts. If any healthy
process *does* sustain 70%, phase 1 extends and CPU stops being a primary threshold.

**Phase 2 — forensics, no killing (7 days, or until the first real incident).** `CW_PHASE=2`.
Bundles and notifications at the *phase-2 candidate* thresholds.

*Advance when:* at least one bundle exists and is complete and readable (all files present,
redaction verified by eye, `sample.txt.gz` decompresses and shows a call graph); **zero** false
notifications; total incidents dir < 1 MB.

**Phase 3 — enforce orphans only (7 days).** `CW_PHASE=3`. Kills only `ppid == 1`. Smallest
blast radius: an orphan has no owner to be surprised, and §8.4's group-signal rule is
simplest there.

*Advance when:* ≥ 1 orphan killed correctly, or 7 days with no candidate; no interactive
session ever entered candidacy at any point in phases 1–3; the `pgid == pid` assumption in
§8.4 confirmed from logged data.

**Phase 4 — enforce all headless.** `CW_PHASE=4`. Steady state. Revert to 3 or 2 on any
false positive.

---

## 13. Failure modes and defences

### 13.1 Killing something legitimate

Five independent layers, any one of which is sufficient:

1. **tty guard (G1)** — structural, not heuristic. Every terminal session is exempt whether or
   not it is labelled. This is the fix for the brief's discriminator (§6.2).
2. **Label guard (G2)** — second, independent signal for wrapper sessions.
3. **RSS 2.4× above the highest ever observed healthy value** (§7.2).
4. **Sustained over the whole window** — a legitimately heavy one-shot that finishes inside
   40 s is never a candidate.
5. **Phase gate** — phases 1–2 cannot signal at all; phase 3 restricts to orphans.

Plus: identity re-confirmed via `lsof … -d txt` immediately before signalling, and
`CW_EXEMPT_PIDS` as a manual escape hatch.

Residual risk: a genuinely enormous legitimate headless run — a 20-minute `claude -p` on a
huge prompt that both exceeds 1.4 GB and pins a core for 40+ s. Phase 1 exists to find out
whether that shape occurs. If it does, the discriminator has to become the RSS *slope*
(a wedge grows monotonically; real work plateaus), which §9's `samples.tsv` already records.

### 13.2 The watchdog itself leaking or wedging

- **~50 s process lifetime.** `StartInterval`, not a resident daemon. A 50-second process
  cannot accumulate a leak.
- **`exec timeout -k 5 55` inside `script.sh`** — the same mechanism `claude-p` uses on
  claude, applied to the watchdog. If `lsof` or `sample` hangs on a pathological process, the
  run dies at 55 s and launchd starts a clean one at the next minute.
- launchd will not overlap runs of the same job, so a slow run cannot pile up.
- **No recursion.** The watchdog invokes `ps`/`lsof`/`sample`/`terminal-notifier` and never
  `claude`, so it cannot create a candidate. `bin/claude-watchdog` is a bash script, so its
  own `ucomm` is `bash` — it cannot match its own detector.

### 13.3 Kill-thrash on the same pid

State file `~/.local/state/claude-watchdog/state.tsv`, keyed on **`pid` + process start time**
(from `etime` at first sighting) so a recycled pid is not confused with the original:

- A pid that has been signalled goes into an **acted set** and is never signalled again. If it
  survives, it is logged `UNKILLABLE` once per run, not re-killed.
- At most **one kill per run** (i.e. per minute). If three claudes wedge at once, they are
  handled over three minutes — spreading the damage rather than doing something drastic all at
  once.
- Global rate limit: **no more than 3 kills per rolling hour**. On the 4th, the watchdog
  notifies "watchdog rate-limited, N candidates outstanding" and stops signalling. A watchdog
  killing things in a loop is a worse failure than the thing it is guarding against.
- Notifications grouped on pid (§8.3), so one incident is one banner.
- Prune state entries for pids that no longer exist, each run — the file cannot grow.

### 13.4 Unbounded logs

**`~/.log/services/` is not rotated by anything.** `bin/ziplog` only touches
`~/.local/share/monitor/*.log.json` (`ziplog:3` cds there; `ziplog:11` globs `*.log.json`)
`[measured]`. Consequently `syncthing.log` is **11 MB**, `copyparty.log` **10 MB**,
`sanctuary.log` **5 MB**, unrotated; the directory totals **54 MB**. `[measured]` A per-minute
service would join them.

Two-part defence:

1. **Log volume by design.** Phase 4 steady state writes **one summary line per run** when
   nothing is over the low bar — ~1440 lines/day, ~150 KB/day. Per-sample detail is written
   only for processes over the low bar. Phase 1 is deliberately chattier and is time-boxed to
   7 days.
2. **`bin/rotate-service-log <name> [threshold-mb]`** — generalise `bin/rotate-inari-log`,
   whose design notes are worth inheriting verbatim `[measured]`:
   - **copytruncate, not rename** — launchd holds an open `O_APPEND` fd on
     `StandardOutPath`, so `mv` leaves launchd writing into the renamed inode and the new file
     never appears until restart. (`rotate-inari-log:5-10`)
   - size-triggered, not daily, so the live log keeps ~a month of greppable content
   - archive named by the date range it *covers*, read from the `ts` prefix
   - write to `mktemp` then `mv` (same dir, atomic); truncate strictly **after** the rename
   - `chmod 700` the archive dir, `600` the archives

   Then add `claude-watchdog` to the existing `org.pancia.inari-logrotate` job (which already
   runs daily at 08:05 `[measured]`) and rename it, or add a second daily entry. Retrofitting
   syncthing/copyparty is an obvious follow-up but out of scope here.

### 13.5 Racing a spawner that is already cleaning up

This is the most likely source of an ugly-but-harmless double-kill: `claude-p`'s `timeout -k 5`
fires, `SIGTERM` goes out, and the watchdog picks the same pid mid-teardown.

- **`CW_MIN_AGE` 90 s / orphan 420 s** puts the watchdog's first opportunity well after every
  in-band deadline it knows about (`claude-p` default 180 s, max configured 300 s + 5 s
  `[measured]`). *Note the ordering:* for a `claude-p` child the in-band deadline at 180–300 s
  is what fires first; the watchdog's 90 s minimum only matters for children with **no**
  deadline. That is deliberate — the watchdog should never be the one to act when a deadline
  exists.
- **Sustained window** — a process in teardown is not over threshold on all 6 samples.
- **Re-verify liveness and re-read `ppid`/`pgid` immediately before each signal.** If the pid
  is gone, or `ppid` changed (reparented to 1 → its spawner just died), re-classify rather
  than proceeding on stale data.
- **`ESRCH` is success, not an error.** If the process vanished between decision and signal,
  log `already-gone` and write the bundle anyway — that bundle is still the evidence.
- Bundle collection happens **before** the signal, so even a race produces forensics.

### 13.6 A `claude` version bump silently disabling detection

`ucomm` is derived from `readlink ~/.local/bin/claude` every run, never hardcoded (§6.1).
Defence in depth: if the derived set contains nothing, or resolves to a path that does not
exist, log `IDENTITY-UNRESOLVED` at warning level and skip the run rather than failing silently
— a watchdog that has quietly stopped watching is the worst outcome in this document.

---

## 14. Testing strategy

The real wedge is not reproducible `[measured]`, so every test synthesises one.

### 14.1 Fake candidate — a decoy binary with the right identity

The detector keys on `ucomm` (executable basename) + `tty == "??"` + argv[0] not
label-shaped. All three are forgeable without any claude:

```
cp /bin/sh /tmp/cw-test/2.1.220      # ucomm becomes 2.1.220
setsid nohup /tmp/cw-test/2.1.220 -c 'while :; do :; done' </dev/null &>/dev/null &
```

`setsid` + redirect gives `tty == "??"`; the spin gives ~100% CPU. Combine with
`CW_RSS_MB=1` for a small-RSS decoy, or a Python one-liner that allocates 1.5 GB and then
spins for the full-shape test. `CW_EXTRA_UCOMM` lets the decoy have any name at all.
This is the workhorse test: it exercises classification, the window, the bundle, and the
ladder end to end, with **zero** risk to a real session.

### 14.2 Real headless claude, artificially over threshold

Run the actual sampler with `CW_RSS_MB=200 CW_CPU_PCT=5 CW_MIN_AGE=5 CW_DRY_RUN=1` while a
genuine `claude-batch` job is running. Confirms: `ucomm=2.1.220` matched, `tty=??`,
ancestry walk finds `CLAUDE_SESSION_ID` in the Bash-tool shell's argv, `lsof` finds the
`tasks/*.output` fd, `sample` succeeds on a real claude. Nothing is killed — `CW_DRY_RUN`
logs the signal it would have sent.

### 14.3 Interactive-safety test — the one that must never fail

With ≥ 3 interactive sessions open, run with `CW_RSS_MB=1 CW_CPU_PCT=0 CW_MIN_AGE=0
CW_DRY_RUN=1`, i.e. thresholds that match *everything*. **Every** interactive session must be
reported exempt, and the exemption reason logged (G1 tty / G2 label). Include a session
started as a **bare `claude`** (unlabelled — §6.2) to prove G1 carries it alone, and one
started via the wrapper to prove G2. This is the regression test; re-run it before every phase
advance.

### 14.4 Orphan test

`setsid` a decoy with `ppid == 1`, and separately let a real `cc-session-review` orphan appear
naturally after an interactive session exits. Assert the real one is **never** a candidate
inside 420 s, and that the decoy is one after it.

### 14.5 Ladder, thrash, and race

- SIGTERM path: decoy that traps `TERM` and exits → assert no SIGKILL, `summary.txt` records
  `TERM`.
- SIGKILL path: decoy that ignores `TERM` → assert escalation after `CW_TERM_GRACE`.
- Unkillable: a `T`-stopped or uninterruptible-sleep decoy → assert `UNKILLABLE` + never-retry.
- Thrash: same decoy across 3 runs → assert signalled once.
- Rate limit: 4 decoys → assert 3 kills then `rate-limited`.
- Race: decoy that exits during the decision window → assert `already-gone`, bundle still
  written, exit status 0.

### 14.6 Self-limits

- Make `lsof` hang (decoy on an unresponsive NFS/`fuse` mount, or an `lsof` shim that
  `sleep 999`s) → assert the run dies at 55 s via `timeout` and the next minute's run is clean.
- Assert one run's total CPU is a small fraction of a second: 6 × 48 ms `ps` + at most one
  121 ms `lsof` + one 2.4 s `sample`. `[measured]`

### 14.7 Rotation

Fabricate a 25 MB `claude-watchdog.log` while the service is running, run
`rotate-service-log`, assert: archive written and gzip-valid, live log truncated to 0, and
launchd's next write lands at offset 0 with no sparse hole — the `O_APPEND` property
`rotate-inari-log` documents. Verify with `lsof +fg -p <launchd-pid>` (look for `AP`).

---

## 15. Open questions

**Q1. Is the tty guard acceptable given it exempts `claude -p` typed at a prompt?**
Recommendation: **yes.** It is the only guard that protects an unlabelled interactive session
(§6.2), and the exempted case is one you are sitting in front of and can Ctrl-C. The right fix
for the one un-deadlined instance — `_claude_release_notes.fish:26` — is to route it through
`claude-p`, a two-word edit.

**Q2. Kill the process group, or the pid plus descendants?**
Recommendation: **group only when `pgid == pid`**, pid-plus-walk otherwise (§8.4). Phase 1
logs `pgid`/`sess` so this is decided on data, not on my reading of GNU `timeout`'s docs.

**Q3. Should an idle orphan (ppid 1, ~400 MB, ~0% CPU, hours old) be killed?**
Recommendation: **no — notify only.** It is indistinguishable from something you `disown`ed on
purpose, and the routine `cc-session-review` orphan has exactly that shape for its first
305 s. 400 MB of leaked RSS is not worth the risk of eating a deliberate background job.
Revisit if phase 1 shows these accumulating.

**Q4. Is 1400 MB the right RSS number?**
Recommendation: **treat it as provisional and re-derive from phase-1 data.** The incident's
2.76 GB is an Activity Monitor *footprint* figure and `ps` RSS reads ~1.28× higher (§4c), so
the two numbers are not on the same scale and 1400 MB may sit lower in the real distribution
than it appears.

**Q5. `terminal-notifier` only, or also a log line I will actually see?**
Recommendation: **add a `chpwd` surface.** A notification banner at 03:00 is gone by morning.
The `.cc/pending-updates` mechanism already proves the pattern — an unread incident bundle
could highlight in `chpwd` the same way. Small, and it means an incident cannot be missed.

**Q6. Should the watchdog also cover the `_bundled` SDK claude under uv caches?**
Recommendation: **yes, via `ucomm == "claude"` (§6.1).** 12 copies exist on disk `[measured]`
and the inari service genuinely runs one. No collision risk found.

**Q7. Retrofit rotation onto `syncthing.log` (11 MB) and `copyparty.log` (10 MB) while
building `rotate-service-log`?**
Recommendation: **build the generic tool, retrofit separately.** It is a real problem
(`~/.log/services/` is 54 MB and rotated by nothing `[measured]`) but it is not this plan's
problem, and bundling it delays the watchdog.

**Q8. Should phase 4 ever be reached, given `claude-p` already exists?**
Recommendation: **yes, but only after phase 3 runs quiet for a week.** The orphan case is the
one nothing else can cover; general headless enforcement is genuinely redundant with a deadline
for every spawner we control, and its value is entirely in covering spawners we forget. That is
worth having — with the least aggressive thresholds the data supports.

---

## 16. Summary of what I am flagging in the brief

| Brief said | Finding | Where |
|---|---|---|
| The proc-label is the interactive/headless discriminator | **Unsound as the primary guard.** Bare `claude` is unlabelled and interactive; `cc -p` is labelled and headless. Use **tty** first, label second. | §6.2 |
| Only 2 threads (vs ~25) marks the runaway | 2 threads is also a healthy claude at t=0.25 s; healthy *idle* headless is 11, not 25. Corroborating field only. | §4(a) |
| Assume an unpredictable hang with no known trigger | `bin/claude-p` documents the exact trigger and already closes it. The watchdog is a **backstop**, and should be scoped and sold as one. | §1 |
| Orphans get a lower bar | Correct in principle, but this machine produces **legitimate** orphaned headless claudes routinely (disowned `cc-session-review`, up to 305 s). Orphan bar needs a 420 s floor and an RSS/CPU gate. | §7.3 |
| Forensics before the kill | Agreed, and `sample PID 2` (2.4 s, 30 KB gz) adds the per-thread call graph — more than the 2026-07-28 reconstruction had. Env capture **must** be redacted. | §9 |
| Log-only rollout first | Agreed and strengthened: `ps` RSS is a different metric from the incident's 2.76 GB, so calibration is not optional. | §4(c), §12 |
| `service create` to register | It scaffolds `KeepAlive true` + a `while true` loop, wrong for a periodic job. Write the three files by hand in the same shapes, then `service start`. | §11 |
| Check whether log growth needs handling | It does. `ziplog` covers only `~/.local/share/monitor/*.log.json`; `~/.log/services/` (54 MB) is rotated by nothing except the inari-specific `rotate-inari-log`. | §13.4 |
