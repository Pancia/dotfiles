# Behaviour tests for critique item 1 (svc restart and an edited svc_cmd).
# Usage: sh test-svc-restart-reread.sh <empty throwaway dir> <bin dir with supervise + svc>
#   <bin dir> = ~/dotfiles/bin           -> shows the defect (restart keeps CMD=v1)
#   <bin dir> = a copy with the patch    -> restart/resume pick up v2/v3; a broken or
#                                           removed svc_cmd keeps the old command
# The bin dir must have ../lib/svc/conf.sh next to it (copy lib/svc too).
# Uses a demo service (`echo CMD=vN; exec sleep 300`), never a real project.
set -u
W="$1"; D="$2"
cd "$W"
export SVC_FS_CONFIG=/nonexistent          # never read the real vault
conf() { printf 'SVC_SERVICES="demo"\nsvc_cmd() { case "$1" in demo) echo '"'"'echo CMD=%s; exec sleep 300'"'"' ;; esac; }\n' "$1" > .svc.conf; }
last() { grep CMD .run/demo.log | tail -1; }

conf v1
SUPERVISE_KEYS=0 "$D/supervise" demo </dev/null >sup.out 2>&1 &
sp=$!; sleep 1.5
echo "0 start                     -> $(last)"

conf v2
"$D/svc" restart demo >/dev/null; sleep 0.5
echo "1 svc restart after edit    -> $(last)   (unpatched: v1, patched: v2)"

conf v3
"$D/svc" suspend demo >/dev/null; "$D/svc" resume demo >/dev/null; sleep 1
echo "2 suspend+resume after edit -> $(last)   (unpatched: v1, patched: v3)"

# A broken config: svc itself cannot source it, so send the request by hand.
printf 'svc_cmd() { case "$1" in demo) echo broken ;;\n' > .svc.conf
"$D/svc" status demo >/dev/null 2>&1; echo "3 svc status, broken config -> exit $?   (svc dies at source time)"
echo restart > .run/demo.req; kill -USR1 "$sp"; sleep 1.5
echo "4 restart, broken config    -> $(last); supervisor alive: $(kill -0 "$sp" 2>/dev/null && echo yes || echo no)"

echo 'true' > .svc.conf                    # svc_cmd removed
echo restart > .run/demo.req; kill -USR1 "$sp"; sleep 1.5
echo "5 restart, svc_cmd removed  -> $(last); supervisor alive: $(kill -0 "$sp" 2>/dev/null && echo yes || echo no)"

echo "pane notes:"; grep '\[supervise\]' sup.out | grep -v pid=
kill -TERM "$sp"; sleep 1.5
pgrep -f 'supervise demo' >/dev/null && echo "WARNING: supervise demo still running" || echo "cleaned up"
