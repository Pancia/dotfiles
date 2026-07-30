# claude-watchdog configuration — sourced by bin/claude-watchdog.
#
# Every value is env-overridable (the `${VAR:-default}` pattern rotate-inari-log
# and claude-p both use), so a one-shot manual run needs no edit here:
#
#   CW_PHASE=1 CW_RSS_MB=200 CW_DRY_RUN=1 ~/dotfiles/bin/claude-watchdog
#
# THRESHOLDS BELOW ARE PROVISIONAL. The incident figure they descend from
# (2.76 GB) is an Activity Monitor *footprint* number, and `ps` RSS reads ~1.28x
# higher than footprint on this machine — the two are not on the same scale. They
# get re-derived from real observations before any phase that can kill. See
# docs/claude-watchdog.md and .cc/PLAN-claude-watchdog.md §4c, §7.2, §15 Q4.

# ---------------------------------------------------------------------------
# Phase — what the watchdog is allowed to DO. Not a threshold.
#
#   1  log only .................... no bundle, no notification, no signal
#   2  log + forensics + notify ..... no signal            <-- current
#   3  as 2, plus SIGTERM/SIGKILL, but only for ppid==1 orphans
#   4  as 3, for every headless candidate
#
# Shipped at 2: phases 1 and 2 of the plan's ladder were merged, because the
# calibration data phase 1 collects and the alerting phase 2 provides carry the
# same risk (none — neither can signal), so running them in sequence would have
# meant a week of recording with nothing watching. Phase 2 therefore does BOTH:
# it logs every headless claude over the low observation bar to build the
# distribution, AND bundles + notifies at the candidate bar.
#
# Phases 3 and 4 stay gated on that data. Advancing is a one-line edit here, and
# reversible; phases 1-2 physically cannot send a signal.
CW_PHASE="${CW_PHASE:-2}"

# ---------------------------------------------------------------------------
# Sampling. 6 samples x 8 s = a 40 s window inside one ~50 s run.
# A candidate must be over threshold on EVERY sample — "sustained, not
# instantaneous" — which is also what filters the fork/exec race described in
# docs/claude-watchdog.md (a claude-spawned child can transiently report the
# parent's accounting name).
CW_SAMPLES="${CW_SAMPLES:-6}"
CW_SAMPLE_INTERVAL="${CW_SAMPLE_INTERVAL:-8}"

# ---------------------------------------------------------------------------
# Observation bar — what gets LOGGED. Deliberately low, so the log builds a
# distribution rather than only recording extremes. Nothing acts on these.
CW_LOG_RSS_MB="${CW_LOG_RSS_MB:-500}"
CW_LOG_CPU_PCT="${CW_LOG_CPU_PCT:-40}"

# ---------------------------------------------------------------------------
# Candidate bar, headless (tty == "??"). All four must hold on every sample.
CW_MIN_AGE="${CW_MIN_AGE:-90}"      # s. Runaway was >60 s; healthy startup burst <2 s.
CW_RSS_MB="${CW_RSS_MB:-1400}"      # 2.4x the highest healthy observation (575 MB).
CW_CPU_PCT="${CW_CPU_PCT:-70}"      # Runaway ~98%. Highest healthy seen: 52.8%, sub-second.
                                    # That 1.4x margin is the thinnest number here — but CPU
                                    # cannot fire alone, and a 52% startup burst sits at
                                    # ~350 MB, failing RSS, age and the sustained window.

# ---------------------------------------------------------------------------
# Candidate bar, orphan (headless AND ppid == 1). Higher age floor, not lower:
# this machine produces legitimate orphaned headless claudes as routine
# behaviour. my-claude-code-wrapper.fish disowns the post-session review, which
# runs CLAUDE_P_TIMEOUT=300 — so a perfectly healthy claude sits at ppid 1,
# tty ??, for up to 305 s. The largest timeout configured anywhere is 300.
CW_ORPHAN_MIN_AGE="${CW_ORPHAN_MIN_AGE:-420}"   # 305 s worst legitimate + ~40% margin
CW_ORPHAN_RSS_MB="${CW_ORPHAN_RSS_MB:-900}"     # ~2.2x healthy headless (~408 MB)
CW_ORPHAN_CPU_PCT="${CW_ORPHAN_CPU_PCT:-50}"    # nobody is coming: a *spinning* orphan is unambiguous

# An IDLE orphan is deliberately never a kill candidate at any phase — ~400 MB
# at ~0% CPU with ppid 1 is exactly what a disowned review looks like, and
# equally what something nohup'd on purpose looks like. It is notified only.
CW_ORPHAN_IDLE_AGE="${CW_ORPHAN_IDLE_AGE:-1800}"   # 30 min
CW_ORPHAN_IDLE_CPU_PCT="${CW_ORPHAN_IDLE_CPU_PCT:-5}"

# ---------------------------------------------------------------------------
# Action limits. Inert at phases 1-2; read here so phase 3 needs no new config.
CW_TERM_GRACE="${CW_TERM_GRACE:-10}"        # s between SIGTERM and SIGKILL
CW_MAX_KILLS_PER_RUN="${CW_MAX_KILLS_PER_RUN:-1}"
CW_MAX_KILLS_PER_HOUR="${CW_MAX_KILLS_PER_HOUR:-3}"
CW_DRY_RUN="${CW_DRY_RUN:-0}"               # 1 = log the signal it would send, send nothing

# ---------------------------------------------------------------------------
# Forensics. A bundle is ~40 KB, 30 KB of that the gzipped `sample` output.
# `sample PID 2` costs 2.4 s, so the per-run cap keeps the run inside its own
# 55 s deadline. Anything deferred by the cap is logged, never dropped silently.
CW_MAX_BUNDLES_PER_RUN="${CW_MAX_BUNDLES_PER_RUN:-3}"
CW_KEEP_INCIDENTS="${CW_KEEP_INCIDENTS:-20}"
CW_SAMPLE_SECONDS="${CW_SAMPLE_SECONDS:-2}"     # duration passed to `sample`

# ---------------------------------------------------------------------------
CW_NOTIFY="${CW_NOTIFY:-1}"                 # 0 disables terminal-notifier
CW_LOG_ROTATE_MB="${CW_LOG_ROTATE_MB:-20}"  # warn only; ~/.log/services/ has no rotator yet

# Max characters kept per argv/env line in a bundle. NOT a cosmetic limit — the
# first bundle written during testing captured a local service's entire
# --system-prompt (33 KB of free-form private content) into a permanent unencrypted
# file, because the sensitive material was the VALUE of an innocuous flag and no
# name-based rule catches that. Owner identification only ever needs the head of
# the line; CLAUDE_SESSION_ID is preserved explicitly even when it falls past the
# cut. Raise this only with that in mind.
CW_ARG_MAXLEN="${CW_ARG_MAXLEN:-400}"

# Extra executable basenames to treat as claude, space-separated. The identity
# set is otherwise derived per run from `readlink ~/.local/bin/claude` plus the
# literal `claude` (the SDK's bundled 192 MB copy). Used by the decoy test.
CW_EXTRA_UCOMM="${CW_EXTRA_UCOMM:-}"

# Never touch these pids, space-separated. Manual escape hatch.
CW_EXEMPT_PIDS="${CW_EXEMPT_PIDS:-}"
