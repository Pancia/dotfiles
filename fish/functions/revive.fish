# What each terminal pane was doing before it died — see docs/revive.md.
#
# A fish function rather than a plain script because picking a ghost up has to
# `cd` and re-run in the caller's shell. Everything read-only is forwarded to
# lib/python/revive.py, which is also what `bin/revive` runs for non-fish callers.

function _revive_py --description 'Run the reader'
    python3 ~/dotfiles/lib/python/revive.py $argv
end

function _revive_go --description 'Focus the iTerm pane that now holds a ghost GUID'
    set -l n $argv[1]
    set -l line (_revive_py get $n)
    or return 1
    set -l guid (string split \t -- $line)[1]
    test -n "$guid"; or return 1
    # Copied rather than shared with _ccs_switch_to: that one is the iTerm arm of
    # a four-way fallback chain, in a file with no tests of its own
    set -l script 'tell application "iTerm2"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if id of s is "'$guid'" then
                        -- wrapped one by one: the iTerm dictionary is not
                        -- uniform about select, and half a focus beats an error
                        try
                            select w
                        end try
                        try
                            select t
                        end try
                        select s
                        return "ok"
                    end if
                end repeat
            end repeat
        end repeat
    end tell'
    # osascript exits 0 whether or not the walk found anything, so the
      # script says so itself
    set -l found (osascript -e "$script" 2>/dev/null)
    if test "$found" != ok
        echo "That pane is gone — iTerm has no session with that id." >&2
        return 1
    end
end

function _revive_pick --description 'Pick up a ghost: cd there, then resume its Claude session, reopen its nvim, or offer its command'
    set -l target $argv[1]
    set -l line (_revive_py get $target)
    or return 1
    set -l parts (string split \t -- $line)
    test (count $parts) -ge 6; or return 1
    set -l cwd $parts[2]
    set -l session $parts[3]
    set -l cmd $parts[4]
    set -l entry $parts[5]
    set -l title $parts[6]
    set -l nvsess $parts[7]
    set -l nvsummary $parts[8]
    set -l answer ""

    # Dismissing deletes the ghost's nvim folder, so it moves aside first, with
    # every nvim's session in it. `revive prune` drops it after a day.
    set -l keep ""
    set -l others
    if test -n "$nvsess"; and test -f "$nvsess"
        set -l aside (_revive_root)/reopen/(path basename -- (path dirname -- $nvsess))-(date +%s)
        mkdir -p (path dirname -- $aside)
        and command mv -f (path dirname -- $nvsess) $aside
        and set keep $aside/(path basename -- $nvsess)
        or set keep ""
        if test -n "$keep"
            for f in $aside/*.vim
                test "$f" != "$keep"; and set -a others $f
            end
        end
    end

    # Dismissed up front: a resumed Claude holds this function for as long as
    # the session lasts, and the banner should not greet the next shell with a
    # ghost that has already been picked up
    _revive_py dismiss $target >/dev/null

    # The journal saw only `revive`, which its readers ignore, and the ghost was
    # just dismissed — so without this a crash from here on leaves no story at all
    set -l story "$cmd"
    if test -n "$session"; and test -f "$entry"
        set story "my-claude-code-wrapper --resume $session"
    else if test -n "$keep"
        # the reopened nvim keeps a session of its own from here on
        set story nvim
    end
    if test -n "$story"; and functions -q _revive_append
        _revive_append cmd "$story"
    end

    if test -n "$cwd"; and test -d "$cwd"
        cd "$cwd"
        echo (set_color brblack)"cd $cwd"(set_color normal)
    else if test -n "$cwd"
        echo (set_color yellow)"$cwd no longer exists — staying put."(set_color normal)
    end

    # Straight in, no question: resuming a conversation re-runs nothing, and
    # it is the whole reason the pane is being revived
    if test -n "$session"; and test -f "$entry"
        test -n "$title"; and echo "⎈ \"$title\""
        if test -n "$keep"
            echo (set_color brblack)"  nvim was open too: $nvsummary — nvim -S $keep"(set_color normal)
        end
        for f in $others
            echo (set_color brblack)"  another nvim: nvim -S $f"(set_color normal)
        end
        functions -q _ccs_resume_entry; or source ~/dotfiles/fish/functions/ccs.fish
        _ccs_resume_entry $entry
        return
    end

    # Reopening files runs nothing, but it is still asked: `n` falls through to
    # the command, so `vims X` or `v` stay one key away
    if test -n "$keep"
        echo "  nvim had open: $nvsummary"
        # The newest is reopened; the rest stay a day, one command away
        for f in $others
            echo (set_color brblack)"  another nvim: nvim -S $f"(set_color normal)
        end
        read -l -P "Reopen them in nvim? [Y/n] " answer
        or return 0
        if test -z "$answer" -o "$answer" = y -o "$answer" = Y
            nvim -S $keep
            command rm -f $keep
            test (count $others) -eq 0; and command rmdir (path dirname -- $keep) 2>/dev/null
            return
        end
        command rm -f $keep
        test (count $others) -eq 0; and command rmdir (path dirname -- $keep) 2>/dev/null
    end

    # An arbitrary command could be anything, so it is shown and confirmed —
    # but Enter means yes, since running it is why you typed `revive`
    if test -n "$cmd"
        echo "  $cmd"
        read -l -P "Run it again? [Y/n] " answer
        or return 0
        if test -z "$answer" -o "$answer" = y -o "$answer" = Y
            eval $cmd
        end
    end
end

function _revive_usage --description 'Show revive usage'
    printf '%s\n' \
        "revive — what each terminal pane was doing before it died" \
        "" \
        "Usage:" \
        "  revive                  Pick up THIS pane's ghost; list them all if it has none" \
        "  revive ls               List panes that left a record behind" \
        "  revive <n>              Pick one up: cd there, resume its Claude session" \
        "                          or offer its command" \
        "  revive here             This pane's ghost in full, with its last commands" \
        "  revive go <n>           Focus the iTerm pane that ghost belongs to" \
        "  revive live             What every currently-journaling pane is doing" \
        "  revive dismiss <n>|here Stop reporting that ghost" \
        "  revive dismiss --all    Stop reporting all of them" \
        "  revive prune [--days N] Drop ghosts older than N days (default 30)" \
        "  revive help             Show this help" \
        "" \
        "Notes:" \
        "  rr is an abbreviation for revive." \
        "  A pane is identified by its iTerm session GUID, which survives a reboot." \
        "  Panes with no journal record but a crashed Claude session are listed too," \
        "  which is the only source for panes older than the journal itself." \
        "  Closing a pane on purpose erases its record; only an unclean death leaves" \
        "  a ghost. A Claude session is resumed with the flags it was launched" \
        "  with; any other command is shown and confirmed first."
end

function revive --description 'Show or pick up what a terminal pane was doing before it died'
    switch "$argv[1]"
        case here live dismiss prune list
            _revive_py $argv
        case ls
            _revive_py list $argv[2..-1]
        case go
            _revive_go $argv[2]
        case banner
            # defined by revive-journal.fish, which only a real shell sources
            functions -q revive-banner; and revive-banner
        case help -h --help
            _revive_usage
        case ''
            # This pane's own ghost if it has one — the banner says `revive`,
            # so that has to mean "this one" — and the listing otherwise
            if _revive_py get here >/dev/null 2>&1
                _revive_pick here
            else
                _revive_py list
            end
        case '--*'
            _revive_py list $argv
        case '*'
            if string match -qr '^[0-9]+$' -- "$argv[1]"
                _revive_pick $argv[1]
            else
                _revive_usage
                return 2
            end
    end
end
