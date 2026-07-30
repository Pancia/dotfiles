function my-claude-code-wrapper --description "Claude Code wrapper" --wraps claude
    # Extract --process-label manually to avoid argparse treating -p as abbreviation
    set -l process_label
    set -l pass_argv
    set -l skip_next 0
    for arg in $argv
        if test $skip_next -eq 1
            set process_label $arg
            set skip_next 0
        else if test "$arg" = --process-label
            set skip_next 1
        else
            set -a pass_argv $arg
        end
    end

    # Sync project skills/agents/commands from .cc-config (or default group).
    # Stamp hashes BOTH .cc-config and the global registry, so adding
    # a command/skill to a group in cc-config.json invalidates stale stamps.
    if test -f .cc-config; or test -d .claude
        set -l config_file ~/dotfiles/ai/cc-config.json
        set -l stamp .claude/.cc-sync-stamp
        set -l cc_hash
        if test -f .cc-config
            set cc_hash (cat .cc-config $config_file | md5 -q)
        else
            set cc_hash (md5 -q $config_file)
        end
        if not test -f $stamp; or test "$cc_hash" != (cat $stamp)
            if test -f .cc-config
                set -l cc_profile (string match -v '//*' < .cc-config | string trim)
                if test -n "$cc_profile"
                    cc-config sync $cc_profile
                end
            else
                set -l default_group (jq -r '.default // empty' $config_file)
                if test -n "$default_group"
                    cc-config sync $default_group
                end
            end
        end
    end

    # Unlock keychain for SSH/mosh sessions so Claude can access stored credentials
    if set -q SSH_CONNECTION
        echo "Unlocking keychain for remote session..."
        security unlock-keychain ~/Library/Keychains/login.keychain-db
        or begin
            echo "Failed to unlock keychain - Claude may not have subscription access"
        end
    end

    set -l timestamp (date +%H:%M:%S)
    set -l label (basename (pwd))
    if test -n "$process_label"
        set label "$label @ $process_label $timestamp"
    else
        set label "$label $timestamp"
    end
    # Skip post-session extras (review + open-session tracking) for non-interactive invocations
    set -l skip_extras 0
    if contains -- -p $pass_argv; or contains -- --print $pass_argv
        set skip_extras 1
    end
    # Skip extras if this invocation is itself processing pending updates
    for arg in $pass_argv
        if string match -q '*/cc:pending-updates*' -- $arg
            set skip_extras 1
            break
        end
    end

    # Claude Code mangles '.' and ':' as well as '/' (~/.claude -> --claude), so
    # replacing only '/' silently pointed at a directory that never exists —
    # which made the post-session review below a no-op for any dotted path,
    # including every .alt/worktrees checkout.
    set -l sessions_dir "$HOME/.claude/projects/"(string replace -a '/' '-' (pwd) | string replace -a '.' '-' | string replace -a ':' '-')

    # Register this invocation in the open-sessions registry so the session stays
    # recoverable after a crash. CCS_ENTRY_FILE is exported so the SessionStart
    # and Stop hooks (bin/ccsave-hook, bin/ccs-title-hook) can stamp the session
    # id and record its title while the session is still alive — a crash is
    # usually power loss, so nothing can run afterwards.
    set -lx CCS_ENTRY_FILE
    if test $skip_extras -eq 0
        # Helpers live in ccs.fish; autoload only picks up the top-level `ccs`
        # function, so source explicitly the first time.
        functions -q _ccs_open_register; or source ~/dotfiles/fish/functions/ccs.fish
        set CCS_ENTRY_FILE (_ccs_open_register $fish_pid)
    end

    proc-label "claude [$label]" claude --verbose $pass_argv

    # Post-session review: find the session JSONL and review in background
    if test $skip_extras -eq 0; and test -d "$sessions_dir"
        set -l post_latest (find "$sessions_dir" -maxdepth 1 -name '*.jsonl' -type f -exec stat -f '%m %N' {} + 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        if test -n "$post_latest"
            echo "📋 Reviewing session for CLAUDE.md updates (background)..."
            # This used to be `&>/dev/null`, which threw away the one signal that a
            # review had failed rather than found nothing (claude-p reports timeouts
            # and errors on stderr). Append instead — a run writes a line or two, and
            # history matters because the failures worth catching are intermittent —
            # but trim first: nothing rotates ~/.log, where services/ has reached 54MB.
            set -l review_log "$HOME/.log/cc-session-review.log"
            if test -f "$review_log"; and test (wc -c < "$review_log" | string trim) -gt 102400
                tail -n 500 "$review_log" > "$review_log.trim"; and mv "$review_log.trim" "$review_log"
            end
            printf '=== %s %s\n' (date '+%Y-%m-%d %H:%M:%S') "$post_latest" >> "$review_log"
            fish -c "cc-session-review '$post_latest'" >>"$review_log" 2>&1 &
            disown

            # Back up session if it's a saved one
            set -l session_id (basename "$post_latest" .jsonl)
            set -l _ccs_dir "$HOME/Cloud/cc-sessions"(pwd)
            if test -f "$_ccs_dir/sessions.json"
                set -l is_saved (jq -r --arg id "$session_id" '[.[].id] | index($id) // empty' "$_ccs_dir/sessions.json" 2>/dev/null)
                if test -n "$is_saved"
                    fish -c "source ~/dotfiles/fish/functions/ccs.fish; _ccs_backup_session '$session_id'" &>/dev/null &
                    disown
                end
            end
        end
    end

    # Clean exit: drop the open-sessions entry. (Both saved and unsaved clean
    # exits delete the file — only crashes leave it behind for recovery.)
    if test $skip_extras -eq 0
        _ccs_open_finalize $fish_pid
    end
end
