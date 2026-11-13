# Shared by bin/ccsave-hook and bin/ccs-title-hook. Source it; it defines
# functions only.

# True when this hook belongs to the claude that the wrapper launched, not a
# nested one. CCS_ENTRY_FILE is inherited by every descendant, so a nested
# `claude -p` (even one resuming the parent's own id) sees the same entry.
#
# The entry records the wrapper's fish pid. Claude runs a hook directly or
# through `sh -c`, so that claude is the hook's parent or grandparent, and its
# parent is the wrapper. A nested claude sits at least one shell deeper, so the
# wrapper is never within two steps of its hooks. pid_lstart guards pid reuse.
_ccs_is_top_claude() {
    local want lstart p i pp
    [ -n "${CCS_ENTRY_FILE:-}" ] && [ -f "$CCS_ENTRY_FILE" ] || return 1
    want=$(jq -r '.pid // empty' "$CCS_ENTRY_FILE" 2>/dev/null)
    lstart=$(jq -r '.pid_lstart // empty' "$CCS_ENTRY_FILE" 2>/dev/null)
    [ -n "$want" ] || return 1
    p=$PPID
    for i in 1 2; do
        pp=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
        [ -n "$pp" ] || return 1
        if [ "$pp" = "$want" ]; then
            [ -z "$lstart" ] && return 0
            [ "$(ps -o lstart= -p "$want" 2>/dev/null | sed 's/^ *//; s/ *$//')" = "$lstart" ]
            return
        fi
        p=$pp
    done
    return 1
}
