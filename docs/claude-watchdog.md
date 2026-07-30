# claude-watchdog

A launchd backstop that watches for a headless `claude` process growing without
bound, records what it finds, and — from phase 3 onward, not yet — kills it.

**Currently at phase 2: it observes, captures forensics, and notifies. It cannot
kill anything.**

| | |
|---|---|
| Service | `org.pancia.claude-watchdog`, `StartInterval 60` |
| Logic | `bin/claude-watchdog` (runnable by hand any time) |
| Config | `services/claude-watchdog/config.sh` |
| Log | `~/.log/services/claude-watchdog.log` |
| Bundles | `~/.local/state/claude-watchdog/incidents/` (`drwx------`, 20 kept) |
| Tests | `services/claude-watchdog/test/run-tests.sh` |
| Design | `.cc/PLAN-claude-watchdog.md` |

## Why it exists

On 2026-07-28 a headless `claude` sat at ~98% CPU with its footprint climbing past
2.7 GB, produced no output, and had to be killed by hand. The trigger is still
unknown and not reproducible — the retired-model theory was tested and disproved
(a retired `--model` exits rc=1 in ~2 s).

It is a **backstop**, not the primary defence. Every spawner in this repo now
carries its own deadline (`bin/claude-p` for shell callers, `asyncio.wait_for` /
`CommandContext` for SDK and subprocess callers), and those fire first by design.
What a deadline cannot cover is the two cases this exists for:

- an **orphan** whose spawner already exited, so nothing is left to time it out
- a **call site added later** that forgets to set a deadline

## Phases

Phase controls what the watchdog may *do*. It is not a threshold. Advancing is a
one-line edit in `config.sh` and is reversible.

| Phase | Log | Bundle | Notify | Signal |
|---|---|---|---|---|
| 1 | ✓ | | | |
| **2 ← current** | ✓ | ✓ | ✓ | |
| 3 | ✓ | ✓ | ✓ | orphans (`ppid == 1`) only |
| 4 | ✓ | ✓ | ✓ | every headless candidate |

The plan defined phase 1 (log only, 7 days) and phase 2 (forensics, 7 days) as
separate stages. **They were merged.** Both carry the same risk — neither can
signal — so running them in sequence would have meant a week of recording with
nothing watching. Phase 2 therefore logs every headless claude *and* alerts at the
candidate bar. Phases 3 and 4 remain gated on the data this phase collects, since
that is where a mistake costs real work.

The kill path is **not implemented** in this build. Setting `CW_PHASE=3` logs a
warning and signals nothing.

## Classification

Applied in order. The first four are guards; a process must survive all of them.

| | Rule | Effect |
|---|---|---|
| G1 | `tty != "??"` | **exempt, unconditionally** |
| G2 | argv[0] matches `claude [...]` (the proc-label shape) | exempt |
| G3 | `ucomm` not in the derived claude set | not a candidate |
| G4 | argv[0] parenthesised (zombie / mid-exec) | skip |
| G5 | argv[0] basename not in the derived claude set | not a candidate |
| C1 | otherwise | headless candidate |
| C2 | C1 and `ppid == 1` | orphan candidate |

**tty is the guard, not the proc-label.** The label means "went through the fish
wrapper", which is not the same as interactive: typing `claude` at a prompt starts
an *unlabelled interactive* session (nothing shadows `claude`; the only binding is
`abbr -a cc my-claude-code-wrapper`), while `cc -p '…'` is a *labelled headless*
one. A label-based guard would have made a real interactive session a kill
candidate.

**Identity is derived every run**, never hardcoded:
`basename "$(readlink ~/.local/bin/claude)"` → today `2.1.220`, plus the literal
`claude` for the SDK's bundled copy. Hardcoding the version would silently stop
watching at the next update.

**G5 was added during the build.** A claude-spawned `ugrep` was twice observed
reporting `ucomm=2.1.220` — the parent's accounting name, during its fork/exec
window. `ucomm` alone is therefore not sufficient identity. Requiring argv[0] to
*also* basename to a claude executable rejects it for free, and the
present-in-every-sample requirement independently filters anything that transient.

## Thresholds

All conditions must hold on **every sample** in the window (6 samples × 8 s).
`%CPU` comes from `time` deltas across samples, never from `pcpu`, which is a
decayed estimate rather than an interval average.

| | Headless | Orphan (`ppid == 1`) |
|---|---|---|
| age | ≥ 90 s | ≥ 420 s |
| RSS | ≥ 1400 MB | ≥ 900 MB |
| CPU | ≥ 70% | ≥ 50% |
| RSS trend | non-decreasing end to end, no drop > 2% between samples | same |

The orphan bar is *higher* on age, not lower, because this machine produces
legitimate orphaned headless claudes routinely: `my-claude-code-wrapper.fish`
disowns the post-session review, which runs `CLAUDE_P_TIMEOUT=300`, so a healthy
claude sits at `ppid 1` for up to 305 s. 420 s is that plus margin.

An **idle** orphan (≥ 30 min, < 5% CPU) is notified and never killed at any phase —
it is indistinguishable from something deliberately `nohup`'d.

### These numbers are provisional

The incident's 2.76 GB is an Activity Monitor **footprint** figure. `ps` RSS is a
different metric — the plan measured it reading ~1.28× *higher* than footprint for
one claude process, while a bundle written during testing showed `ps` RSS 189 MB
against a footprint of 195.4 MB, i.e. ~0.97×. The relationship is not a constant,
so 1400 MB cannot be treated as calibrated. Re-derive from the log before enabling
any phase that kills.

Early observations, for reference: healthy **headless** claude sat at **114–172 MB**
across a session, well under the 387–408 MB the plan measured; interactive sessions
ranged 261–508 MB with a max of 575 MB (499 MB seen since).

**The 2% RSS-drop tolerance is likely too tight.** Healthy headless claude was
observed jittering downward by 2.2%, 3.1%, 3.3%, 4.6% and 7.8% between consecutive
samples in the first fifteen runs. The trend rule currently rejects a candidate on
any drop above 2%, so if a real wedge jitters like a healthy process does, the trend
gate could suppress detection rather than only suppressing false positives. Every
`obs` line records `drop%`, so raise this from the log — do not raise it by taste.

## Reading the log

`service log claude-watchdog -q -p`

```
cw: run phase=2 ids=2.1.220,claude exempt_tty=6 exempt_label=0 headless=2 orphan=0
    partial=0 exempt_rss_max=368MB headless_rss_max=137MB headless_cpu_max=2.5%
    candidates=0 bundles=0 deferred=0
cw: obs pid=91124 class=HEADLESS tty=?? age=458s rss=125-131MB(125->131 up drop0.4%)
    cpu=2.0-2.5% th=16 ppid=90988 pgid=90985 sess=0
cw:   smp pid=91124 t=0s rss=131MB cpu_acc=9.2s age=458s th=16 stat=S
cw: CANDIDATE pid=... (as obs)
cw: bundle /Users/anthony/.local/state/claude-watchdog/incidents/<stamp>-pid<pid>
cw: DEFERRED pid=... — per-run bundle cap reached; will bundle next run
```

- `obs` — one line per headless claude per run, **unconditionally**. Healthy
  headless claude sits below any bar worth alerting on, so gating these on the
  observation bar would have made the distribution unknowable.
- `smp` — per-sample detail, only for processes over the observation bar
  (500 MB or 40% CPU).
- `run` — emitted only when at least one claude process was classified. When the
  machine has none, a single `heartbeat` line appears once an hour, so a long
  silence is distinguishable from a dead watchdog.
- `partial=N` — processes that appeared in some samples but not all. Expected for
  short-lived children; never candidates.

## Reading a bundle

| File | What it answers |
|---|---|
| `summary.txt` | verdict, thresholds in force, phase, whether anything was signalled |
| `samples.tsv` | the RSS/CPU curve — the most diagnostic artefact, and what the 2026-07-28 reconstruction never had |
| `sample.txt.gz` | per-thread call graph. For a startup hang this names the function. Also carries Physical footprint and **peak** footprint |
| `ancestry.txt` | ppid walk to pid 1. Where the owning session appears |
| `openfiles.txt` | the only owner evidence left once `ppid == 1`. A `tasks/*.output` fd is what traced the owner on 2026-07-28 |
| `exe.txt` | authoritative executable path (`lsof -d txt`). `ucomm` is a 16-char truncation and is not authoritative enough to kill on |
| `proc.txt`, `env.txt`, `system.txt` | invocation, redacted environment, machine-wide context |

### Redaction is load-bearing, and credentials are not the main risk

Bundles are permanent, unencrypted, and covered by no backup. Three rules apply to
everything carrying argv or env:

1. **Bulk-content flag values are dropped entirely.** On seeing
   `--system-prompt`, `--append-system-prompt`, `-p`, `--print`, `--mcp-config`,
   `--settings`, `--allowedTools`, `--disallowedTools`, the **whole remainder of
   the line** is discarded.
2. **Name-based:** the value of anything whose name contains `KEY`, `TOKEN`,
   `SECRET`, `PASSWORD`, `CREDENTIAL` or `AUTH`. Name-based so it fails safe on
   shapes that do not exist yet.
3. **Shape-based:** `rotate-inari-log`'s token pattern, over the whole stream.
4. **Hard line truncation** at `CW_ARG_MAXLEN` (400) as the backstop for payloads
   in flags nobody anticipated. `CLAUDE_SESSION_ID` is lifted out and re-appended
   if it falls past the cut, since it is the one field worth keeping.

Rule 1 exists because of what happened while testing this. The first bundle traced
a headless claude to a long-running local service — correctly — and captured its
entire `--system-prompt` in the process: 33 KB of free-form private personal
content, written to a permanent file. Not one byte of it matched any credential
pattern, because the sensitive material was the *value of an innocuous flag*.

The first fix ended the redaction at "the next token that looks like a flag" —
which is **not sufficient**: a prompt is free text and can contain a flag-shaped
token (`--days` did), re-opening capture mid-prompt. Hence dropping the entire rest
of the line. Trailing flags like `--model` are lost with it; that is the right
trade, since `exe.txt` carries authoritative identity and `samples.tsv` carries
behaviour.

Those test bundles were destroyed. If `CW_ARG_MAXLEN` is ever raised, re-read this
section first.

## Self-limits

- **~50 s lifetime**, via `StartInterval` rather than a resident daemon. A
  50-second process cannot accumulate a leak.
- **`exec timeout -k 5 55`** in `script.sh` — the same mechanism `claude-p` applies
  to claude, applied to the watchdog. Verified: rc=124 at 55 s.
- launchd will not overlap runs of the same job.
- **No recursion.** It invokes `ps`/`lsof`/`sample`/`terminal-notifier` and never
  `claude`. It is a bash script, so its own `ucomm` is `bash` and it cannot match
  its own detector.
- Cost per run: 6 × ~48 ms `ps`, ~5 ms per headless claude for the thread count
  (macOS has no `thcount`/`nlwp` keyword), and 2.4 s for `sample` only when a
  bundle is written. A default run measured **41 s** wall, almost all of it the
  sampling window.
- Bundles are capped at 3 per run so the run stays inside its deadline. Anything
  deferred is **logged**, never silently dropped.

**Actual cadence is ~101 s, not 60 s.** `StartInterval 60` does not mean "every
60 s" when the job takes 41 s — launchd restarts the countdown after the job exits,
so observed run starts were 101–102 s apart. Detection latency is therefore up to
~160 s (40 s window + up to ~60 s of gap) rather than the ~100 s the design
targeted. That is fine for observing and alerting. If phase 3 ever needs tighter
latency, shorten the sampling window rather than the interval — a shorter interval
just adds idle wakeups.

## Testing

```bash
services/claude-watchdog/test/run-tests.sh          # 29 assertions, ~90s
services/claude-watchdog/test/run-tests.sh --slow   # plus the 55s deadline test
```

Safe to run any time: tests use an isolated `CW_STATE_DIR`, never raise the phase,
and the only process any test kills is its own decoy.

The decoy (`test/cw-decoy.c`) forges the three properties the detector keys on and
can reproduce the incident shape — a pinned core with a climbing resident set. Its
header documents three ways an earlier version silently did nothing, all worth
knowing before writing anything that tries to move RSS on macOS: a copied
Apple-signed binary is SIGKILLed at exec; `memset` to a constant is collapsed by
the memory compressor; and a non-escaping allocation is deleted by the optimiser.

`T1` is the test that must never fail: with **every threshold set to zero**, no
process holding a controlling tty may be classified, let alone become a candidate,
and `exempt_tty` must match independent `ps` ground truth.

## Advancing to phase 3

Do not, until the log supports it. Required first:

1. Re-derive `CW_RSS_MB` from observed healthy `ps` RSS (the plan suggests
   p100 × 3, floored at 1 GB). The shipped 1400 MB is provisional.
2. Confirm no healthy headless claude sustains `CW_CPU_PCT` across a full window.
   This is the thinnest margin in the design: the highest healthy CPU measured was
   52.8%, against a 70% threshold — though CPU cannot fire alone.
3. Confirm the legitimate `cc-session-review` orphans appear with the lifetimes
   §7.3 predicts.
4. Settle whether to signal the process group or the pid plus a descendant walk.
   Every sample records `pgid` and `sess` for this. **Early data contradicts the
   plan's assumption:** two headless claudes showed `pgid != pid` (pid 91124 with
   `pgid 90985`), so the group-signal shortcut is not generally available and the
   pid-plus-walk path is the one that matters.
5. Implement the kill ladder, which this build does not contain.

## Known gaps

- **`~/.log/services/` is rotated by nothing.** It was 54 MB before this service
  existed (`syncthing.log` 11 MB, `copyparty.log` 10 MB); `ziplog` only covers
  `~/.local/share/monitor/*.log.json`. A per-minute service adds to that. The
  watchdog warns when its own log passes `CW_LOG_ROTATE_MB`, and only when the size
  has grown since the last warning. A generic `bin/rotate-service-log` —
  copytruncate, not rename, because launchd holds an `O_APPEND` fd — is the fix and
  is not built.
- `claude -p` typed at a prompt inherits the shell's tty and is exempt (G1). An
  accepted false negative; the fix is in-band, at the call site.
