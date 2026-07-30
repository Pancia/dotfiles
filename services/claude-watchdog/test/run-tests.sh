#!/usr/bin/env bash
# claude-watchdog test suite.
#
#   ./run-tests.sh          the fast tests (~70 s)
#   ./run-tests.sh --slow   also the 55 s self-deadline test
#
# Everything runs against an isolated CW_STATE_DIR under a temp dir, so a test run
# never touches real incident bundles or the real dedup state.
#
# Safe to run any time: the watchdog cannot signal below phase 3, and no test ever
# raises the phase. The only process any test kills is its own decoy.
set -uo pipefail

WATCHDOG="${WATCHDOG:-$HOME/dotfiles/bin/claude-watchdog}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SLOW=0
[ "${1:-}" = --slow ] && SLOW=1

WORK=$(mktemp -d "${TMPDIR:-/tmp}/cw-test.XXXXXX") || exit 1
export CW_STATE_DIR="$WORK/state"
DECOY_PID=""
cleanup() {
    [ -n "$DECOY_PID" ] && kill -9 "$DECOY_PID" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail + 1)); }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# The decoy is named after the LIVE claude version, so the test exercises the real
# runtime-derived identity set rather than a CW_EXTRA_UCOMM shortcut.
VER=$(basename "$(readlink "$HOME/.local/bin/claude" 2>/dev/null)" 2>/dev/null)
if [ -z "$VER" ] || [ "$VER" = . ]; then
    echo "cannot derive claude version from ~/.local/bin/claude — aborting"
    exit 1
fi

head_ "build decoy as '$VER'"
cc -O0 -o "$WORK/$VER" "$HERE/cw-decoy.c" 2>&1 || { bad "compile"; exit 1; }
ok "compiled $WORK/$VER"

# 20 MB held, +2 MB/s, one core pinned — a scaled-down incident shape. tty is
# inherited: this must be launched from something that already has none (a Claude
# Code Bash tool, a launchd job) for the decoy to classify as headless.
"$WORK/$VER" 20 2 </dev/null >/dev/null 2>&1 &
DECOY_PID=$!
sleep 12
if ! kill -0 "$DECOY_PID" 2>/dev/null; then
    bad "decoy died immediately (a COPIED system binary would — see cw-decoy.c)"
    exit 1
fi
DECOY_TTY=$(ps -o tty= -p "$DECOY_PID" | tr -d ' ')
check "$([ "$DECOY_TTY" = '??' ] && echo 0 || echo 1)" "decoy has no controlling tty (got '$DECOY_TTY')"
DECOY_RSS=$(ps -o rss= -p "$DECOY_PID" | tr -d ' ')
check "$([ "${DECOY_RSS:-0}" -gt 10000 ] && echo 0 || echo 1)" \
    "decoy holds a real resident set (${DECOY_RSS}KB — an optimised-away or memset decoy shows ~1MB)"

# ---------------------------------------------------------------------------
head_ "T1  interactive safety — the test that must never fail"
# Every threshold at zero. Nothing holding a controlling tty may be classified,
# let alone become a candidate, at ANY threshold.
truth_tty=$(ps -axo tty=,ucomm= | awk -v v="$VER" '$2 == v || $2 == "claude"' | awk '$1 != "??"' | grep -c .)
out=$(CW_MIN_AGE=0 CW_RSS_MB=0 CW_CPU_PCT=0 \
      CW_ORPHAN_MIN_AGE=0 CW_ORPHAN_RSS_MB=0 CW_ORPHAN_CPU_PCT=0 \
      CW_SAMPLES=3 CW_SAMPLE_INTERVAL=2 CW_NOTIFY=0 CW_MAX_BUNDLES_PER_RUN=0 \
      "$WATCHDOG" 2>&1)

# Note the `!`: `grep -qv PATTERN` succeeds when it FINDS a line lacking the
# pattern, which is the failure condition here, so the polarity has to be flipped.
! printf '%s\n' "$out" | grep -E '^cw: (obs|CANDIDATE|ORPHAN)' | grep -qv 'tty=??'
check "$?" "no process with a controlling tty was classified at all"
! printf '%s\n' "$out" | grep -E '^cw: (CANDIDATE|ORPHAN-CANDIDATE|ORPHAN-IDLE)' | grep -qv 'tty=??'
check "$?" "no process with a controlling tty became a candidate"
got_exempt=$(printf '%s\n' "$out" | sed -n 's/.*exempt_tty=\([0-9]*\).*/\1/p' | tail -1)
check "$([ "${got_exempt:-x}" = "$truth_tty" ] && echo 0 || echo 1)" \
    "exempt_tty=$got_exempt matches independent ps ground truth ($truth_tty)"

# ---------------------------------------------------------------------------
head_ "T2  decoy detection, bundle, and the no-silent-cap path"
out=$(CW_ORPHAN_MIN_AGE=5 CW_ORPHAN_RSS_MB=10 CW_ORPHAN_CPU_PCT=50 \
      CW_MIN_AGE=5 CW_RSS_MB=10 CW_CPU_PCT=50 \
      CW_SAMPLES=3 CW_SAMPLE_INTERVAL=2 CW_NOTIFY=0 "$WATCHDOG" 2>&1)
printf '%s\n' "$out" | grep -qE "^cw: (CANDIDATE|ORPHAN-CANDIDATE) pid=$DECOY_PID "
check "$?" "decoy became a candidate on its forged identity"
BUNDLE=$(ls -1dt "$CW_STATE_DIR"/incidents/*-pid"$DECOY_PID" 2>/dev/null | head -1)
check "$([ -n "$BUNDLE" ] && echo 0 || echo 1)" "forensic bundle written"

if [ -n "$BUNDLE" ]; then
    for f in summary.txt samples.tsv proc.txt ancestry.txt env.txt openfiles.txt exe.txt system.txt; do
        check "$([ -s "$BUNDLE/$f" ] && echo 0 || echo 1)" "bundle has non-empty $f"
    done
    gzip -t "$BUNDLE/sample.txt.gz" 2>/dev/null
    check "$?" "sample.txt.gz is a valid gzip"
    gzip -dc "$BUNDLE/sample.txt.gz" 2>/dev/null | grep -q 'Call graph'
    check "$?" "sample.txt.gz contains a call graph"
    n=$(awk 'END { print NR }' "$BUNDLE/samples.tsv")
    check "$([ "$n" = 4 ] && echo 0 || echo 1)" "samples.tsv has a header plus 3 sample rows (got $n)"
    perm=$(stat -f%Sp "$BUNDLE")
    check "$([ "$perm" = "drwx------" ] && echo 0 || echo 1)" "bundle dir is $perm"
    grep -q 'signal sent:    none' "$BUNDLE/summary.txt"
    check "$?" "summary records that nothing was signalled"
fi

out=$(CW_ORPHAN_MIN_AGE=5 CW_ORPHAN_RSS_MB=10 CW_ORPHAN_CPU_PCT=50 \
      CW_MIN_AGE=5 CW_RSS_MB=10 CW_CPU_PCT=50 CW_MAX_BUNDLES_PER_RUN=0 \
      CW_SAMPLES=3 CW_SAMPLE_INTERVAL=2 CW_NOTIFY=0 "$WATCHDOG" 2>&1)
printf '%s\n' "$out" | grep -q 'still-present (already bundled'
check "$?" "T3  second sighting does not re-bundle (dedup on pid + start time)"
before=$(ls -1d "$CW_STATE_DIR"/incidents/*-pid* 2>/dev/null | grep -c .)
check "$([ "$before" = 1 ] && echo 0 || echo 1)" "T3  exactly one bundle exists after two detections (got $before)"

# ---------------------------------------------------------------------------
head_ "T4  redaction — bulk argv values must never reach a bundle"
# A decoy invoked with claude-shaped bulk-content flags carrying a marker string.
{ kill -9 "$DECOY_PID" 2>/dev/null; wait "$DECOY_PID"; } 2>/dev/null; sleep 1
MARKER="SENSITIVE-PAYLOAD-DO-NOT-CAPTURE"
"$WORK/$VER" 20 2 --system-prompt "$MARKER $MARKER $MARKER" --model "opus-$MARKER" \
    </dev/null >/dev/null 2>&1 &
DECOY_PID=$!
sleep 10
rm -rf "$CW_STATE_DIR/incidents" "$CW_STATE_DIR/state.tsv"
CW_ORPHAN_MIN_AGE=5 CW_ORPHAN_RSS_MB=10 CW_ORPHAN_CPU_PCT=50 \
CW_MIN_AGE=5 CW_RSS_MB=10 CW_CPU_PCT=50 \
CW_SAMPLES=3 CW_SAMPLE_INTERVAL=2 CW_NOTIFY=0 "$WATCHDOG" >/dev/null 2>&1
BUNDLE=$(ls -1dt "$CW_STATE_DIR"/incidents/*-pid"$DECOY_PID" 2>/dev/null | head -1)
if [ -n "$BUNDLE" ]; then
    ! grep -rq "$MARKER" "$BUNDLE" 2>/dev/null
    check "$?" "the --system-prompt payload appears nowhere in the bundle"
    grep -q 'REDACTED' "$BUNDLE/proc.txt"
    check "$?" "proc.txt records that a redaction happened"
    grep -q "$(basename "$WORK")\|$VER" "$BUNDLE/exe.txt"
    check "$?" "exe.txt still carries the authoritative executable path"
    longest=$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' "$BUNDLE/env.txt")
    check "$([ "$longest" -le 700 ] && echo 0 || echo 1)" \
        "env.txt lines are bounded (longest $longest chars)"
else
    bad "T4 bundle was not written"
fi

# ---------------------------------------------------------------------------
if [ "$SLOW" = 1 ]; then
    head_ "T5  self-limits — the run must die at its own deadline"
    start=$(date +%s)
    CW_SAMPLES=100 CW_SAMPLE_INTERVAL=5 CW_NOTIFY=0 \
        "$HOME/dotfiles/services/claude-watchdog/script.sh" >/dev/null 2>&1
    rc=$?; el=$(( $(date +%s) - start ))
    check "$([ "$rc" = 124 ] && echo 0 || echo 1)" "script.sh exits 124 (got $rc)"
    check "$([ "$el" -ge 50 ] && [ "$el" -le 62 ] && echo 0 || echo 1)" "killed at ~55s (got ${el}s)"
else
    printf '\n(skipping the 55s self-deadline test; pass --slow to include it)\n'
fi

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
[ "$fail" = 0 ]
