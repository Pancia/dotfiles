# Per-pane journal — what each terminal pane was doing, so a pane that iTerm
# restores after a crash can say what it was for. The read side is `revive`.
#
# Sourced from config.fish; event handlers cannot be autoloaded.
#
# One record per pane under $XDG_STATE_HOME/term-sessions/live/, keyed by the
# iTerm session GUID. The GUID survives a reboot — the wNtMpK prefix in front of
# it does not — so only the GUID is identity. A shell that starts in a pane whose
# record still has a dead owner renames that record into ghosts/ before writing
# its own: one atomic rename, and a ghost exists only once someone has adopted it.
#
# The hot path forks nothing — printf, string, math and the redirect are all
# builtins, and the record is appended to rather than rewritten. One `ps` runs at
# shell start (to record who owns the pane) and a second only when an orphan is
# actually found.
#
# Docs: docs/revive.md

function _revive_root --description 'Root of the per-pane journal store'
    if test -n "$XDG_STATE_HOME"
        echo $XDG_STATE_HOME/term-sessions
    else
        echo $HOME/.local/state/term-sessions
    end
end

function _revive_pane_key --description 'Stable per-pane identity, or nothing'
    set -l sid "$ITERM_SESSION_ID"
    test -n "$sid"; or set sid "$TERM_SESSION_ID"
    test -n "$sid"; or return 1
    # wNtMpK:GUID — the prefix is reassigned on restore, the GUID is not
    set -l key (string replace -r '^w[0-9]+t[0-9]+p[0-9]+:' '' -- "$sid")
    test -n "$key"; or return 1
    # tmux multiplexes many shells onto one pane; keep their records apart
    if set -q TMUX; and test -n "$TMUX_PANE"
        set key "$key"-(string replace -a '%' '' -- "$TMUX_PANE")
    end
    string replace -ra '[^A-Za-z0-9._-]' _ -- "$key"
end

function _revive_append --description 'Append one key/value line to this pane record'
    test -n "$__revive_rec"; or return
    # Quoted: an empty command substitution is an empty *list* in fish, which
    # would drop the field and leave printf reusing its format
    set -l encoded (string escape --style=url -- "$argv[2]")
    printf '%s\t%s\n' $argv[1] "$encoded" >>$__revive_rec
    set -g __revive_lines (math $__revive_lines + 1)
    if test $__revive_lines -gt 500
        _revive_compact
    end
end

function _revive_field --description 'Read one scalar field out of a record'
    set -l file $argv[1]
    set -l want $argv[2]
    set -l value ""
    set -l parts
    while read -l line
        set parts (string split -m1 \t -- $line)
        test (count $parts) -eq 2; or continue
        if test "$parts[1]" = "$want"
            set value (string unescape --style=url -- "$parts[2]" | string collect)
        end
    end <$file
    echo $value
end

function _revive_owner_alive --description 'Is the pid that wrote a record still that same process?'
    set -l pid "$argv[1]"
    set -l lstart "$argv[2]"
    test -n "$pid"; or return 1
    # pid alone is not enough: after a reboot the low pids are handed straight
    # back out, so a dead shell's pid is very likely alive as something else
    set -l now (ps -o lstart= -p $pid 2>/dev/null | string trim)
    test -n "$now"; or return 1
    test "$now" = "$lstart"
end

function _revive_claude_title --description 'Newest Claude session title recorded in this pane'
    set -l guid "$argv[1]"
    set -l lstart "$argv[2]"
    test -n "$guid"; or return
    set -l dir "$HOME/.local/state/claude-sessions/open"
    test -n "$XDG_STATE_HOME"; and set dir "$XDG_STATE_HOME/claude-sessions/open"
    test -d "$dir"; or return
    set -l hits (grep -ls -- "$guid" $dir/*.json 2>/dev/null)
    test (count $hits) -gt 0; or return
    # Only a session started while the dead shell was alive — the same bound
    # revive.py applies — or an older crash in this pane gets advertised here
    # and then skipped by `revive`. An entry is last written after it starts,
    # so its mtime is a safe proxy for started_at without a jq per hit.
    set -l since (date -j -f '%a %b %d %T %Y' "$lstart" +%s 2>/dev/null)
    if test -n "$since"
        set -l fresh
        for h in $hits
            test (stat -f %m $h 2>/dev/null) -ge $since; and set -a fresh $h
        end
        set hits $fresh
        test (count $hits) -gt 0; or return
    end
    set -l newest (command ls -t $hits 2>/dev/null)[1]
    test -n "$newest"; or return
    set -l found (grep -o '"title": *"[^"]*"' "$newest" 2>/dev/null)[1]
    test -n "$found"; or return
    string replace -r '^"title": *"' '' -- "$found" | string replace -r '"$' ''
end

function _revive_render_banner --description 'Format a ghost record as the startup banner'
    set -l ghost $argv[1]
    set -l cwd ""
    set -l guid ""
    set -l lstart ""
    set -l cmds
    set -l closed
    set -l parts
    set -l one
    while read -l line
        set parts (string split -m1 \t -- $line)
        test (count $parts) -eq 2; or continue
        set one (string unescape --style=url -- "$parts[2]" | string collect | string replace -ra '\s+' ' ' | string trim)
        switch $parts[1]
            case cwd
                set cwd "$one"
            case guid
                set guid "$one"
            case lstart
                set lstart "$one"
            case cmd
                set -a cmds "$one"
                set -a closed no
            case done
                test (count $closed) -gt 0; and set closed[-1] yes
        end
    end <$ghost

    # A pane that only ever sat at a prompt has nothing worth interrupting for.
    # It still gets the ⟲ glyph — that is what an empty banner file means.
    test (count $cmds) -gt 0; or return

    set -l when (stat -f '%Sm' -t '%b %e %H:%M' $ghost 2>/dev/null | string trim)
    set -l shown (string replace -r "^$HOME" '~' -- "$cwd")
    echo (set_color --bold d7871f)"⟲ Before it died, this pane was in $shown"(set_color normal)(set_color brblack)"  (last active $when)"(set_color normal)
    if test "$closed[-1]" = no
        echo "    running  $cmds[-1]"
    else
        echo "    last     $cmds[-1]"
    end
    # a tmux record's guid is <iTerm guid>-<pane>; ccs only saw the iTerm half
    set -l bare (string match -r '^[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}' -- "$guid")
    test -n "$bare"; or set bare "$guid"
    set -l title (_revive_claude_title "$bare" "$lstart")
    test -n "$title"; and echo "    ⎈ \"$title\""
    if test (count $cmds) -gt 1
        set -l first (math (count $cmds) - 3)
        test $first -lt 1; and set first 1
        echo "  recent:"
        for c in $cmds[$first..-2]
            echo "    $c"
        end
    end
    # Bare `revive` picks up this pane, so the banner needs no ghost number —
    # which it could not know anyway: numbering is only settled at listing time
    set -l what "pick this up"
    test -n "$title"; and set what "resume that session"
    echo (set_color brblack)"    revive to $what · revive ls for every pane · revive dismiss here"(set_color normal)
end

function _revive_compact --description 'Rewrite an overgrown record: header plus recent commands'
    test -n "$__revive_rec"; or return
    test -f "$__revive_rec"; or return
    set -l hkeys
    set -l hlines
    set -l tail
    set -l parts
    set -l at
    while read -l line
        set parts (string split -m1 \t -- $line)
        test (count $parts) -eq 2; or continue
        switch $parts[1]
            case cmd done
                set -a tail $line
            case '*'
                # scalars are last-wins, and `cwd` is rewritten on every cd —
                # keeping every one of them would defeat the compaction
                if set at (contains -i -- $parts[1] $hkeys)
                    set hlines[$at] $line
                else
                    set -a hkeys $parts[1]
                    set -a hlines $line
                end
        end
    end <$__revive_rec
    if test (count $tail) -gt 40
        set tail $tail[-40..-1]
    end
    printf '%s\n' $hlines $tail >$__revive_rec.tmp
    and mv -f $__revive_rec.tmp $__revive_rec
    set -g __revive_lines 0
end

function _revive_start --description 'Claim this pane, adopting whatever its predecessor left'
    set -g __revive_rec ""
    set -g __revive_pending ""
    set -g __revive_lines 0
    status is-interactive; or return

    set -l key (_revive_pane_key)
    test -n "$key"; or return

    set -l root (_revive_root)
    set -l rec $root/live/$key.rec
    set -l pending $root/pending/$key
    mkdir -p $root/live $root/ghosts $root/pending 2>/dev/null; or return

    set -l lstart (ps -o lstart= -p $fish_pid 2>/dev/null | string trim)
    set -l prev_pid ""
    set -l prev_lstart ""
    set -l ghost ""

    if test -f $rec
        set prev_pid (_revive_field $rec pid)
        set prev_lstart (_revive_field $rec lstart)
        if _revive_owner_alive "$prev_pid" "$prev_lstart"
            # A nested interactive shell. The outer one already speaks for this
            # pane, and two writers would interleave into one record.
            return
        end
        set ghost $root/ghosts/$key-(date +%s).rec
        if mv -f $rec $ghost 2>/dev/null
            # `exec` keeps both the pid and the start time, so a shell reload is
            # not a crash — roll the record over, but do not announce it.
            if test "$prev_pid" != "$fish_pid"; or test "$prev_lstart" != "$lstart"
                # A shell that died without running anything has nothing to add,
                # so the pane's last real story stands. Overwriting it here is
                # what lost the banner on every crash after the first.
                set -l banner (_revive_render_banner $ghost)
                if test (count $banner) -gt 0
                    printf '%s\n' $banner >$pending
                else if not test -s $pending
                    true >$pending
                end
            end
        end
    end

    set -g __revive_rec $rec
    set -g __revive_pending $pending
    _revive_append guid "$key"
    _revive_append wtp "$ITERM_SESSION_ID"
    _revive_append pid $fish_pid
    _revive_append lstart "$lstart"
    _revive_append term "$TERM_PROGRAM"
    _revive_append cwd "$PWD"
end

function _revive_on_preexec --on-event fish_preexec
    test -n "$__revive_rec"; or return
    # A whitespace-only commandline still fires this event (a truly empty one
    # does not), and it is not worth a history slot
    set -l trimmed (string trim -- "$argv[1]")
    test -n "$trimmed"; or return
    _revive_append cmd "$argv[1]"
end

function _revive_on_postexec --on-event fish_postexec
    set -l code $status
    test -n "$__revive_rec"; or return
    set -l trimmed (string trim -- "$argv[1]")
    test -n "$trimmed"; or return
    _revive_append done "$code $CMD_DURATION"
end

function _revive_on_exit --on-event fish_exit
    test -n "$__revive_rec"; or return
    # Closing a pane on purpose must not look like a crash. Verified: this fires
    # on `exit` and when the terminal goes away, and not on SIGKILL or a power
    # cut — exactly the line a ghost has to fall on.
    command rm -f $__revive_rec 2>/dev/null
end

function reviveRecordCwd --description 'Note this pane directory in its journal'
    test -n "$__revive_rec"; or return
    _revive_append cwd "$PWD"
end

function revive-banner --description 'Print this pane ghost banner, if it has one'
    test -n "$__revive_pending"; or return
    test -s "$__revive_pending"; or return
    while read -l line
        echo $line
    end <$__revive_pending
end

_revive_start
