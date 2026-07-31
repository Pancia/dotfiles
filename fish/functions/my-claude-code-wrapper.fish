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

    # --- per-session worktree isolation -----------------------------------
    # In a repo opted in with `cc-worktree on`, run this session in its own
    # git worktree / jj workspace so two sessions in one checkout cannot tread
    # on each other. Everything below this point therefore runs in the worktree.
    #
    # skip_extras gating is load-bearing: ai.fish, ai_health, ai_inbox, ccpu and
    # sanctuary/main-claude all route through this wrapper with -p, and would
    # otherwise leak a worktree per run AND get an empty checkout to inspect.
    #
    # Full mechanism, and why each guard exists: docs/cc-worktree.md.
    # ~/dotfiles cannot be isolated and is refused by name — there the answer is
    # ccjj / commit-mine, docs/cc-jj-sessions.md.
    set -l _cc_orig_pwd $PWD
    set -l _cc_wt_slot ""
    set -l _cc_resume_slot
    set -l _cc_resume_sid
    set -l _cc_slot
    set -l _cc_target
    set -l _cc_rc 0
    if test $skip_extras -eq 0
        # Slot-aware resume: `claude --resume` is scoped to the project
        # directory (Claude Code keys transcripts by mangled cwd), so a session
        # that ran in w-03 can only be resumed from w-03. Without this it fails
        # with "No conversation found with session ID".
        set _cc_resume_sid (__cc_resume_id $pass_argv)
        if test -n "$_cc_resume_sid"
            set _cc_slot (cc-worktree slot-for-session $_cc_resume_sid)
            if test -n "$_cc_slot"
                set _cc_resume_slot --slot $_cc_slot --reuse
            end
        end
        # NO 2>&1: `create` prints warnings on the SUCCESS path (dirty parent,
        # subdir fallback, submodules). Folding them into the capture makes
        # $_cc_target a multi-element list, `cd` fails with "Too many args", and
        # $status is STILL 0 — so the wrapper would run un-isolated with a slot
        # claimed. Path on stdout, warnings on stderr, and index defensively.
        set _cc_target (cc-worktree create --pid $fish_pid $_cc_resume_slot)
        set _cc_rc $status
        switch $_cc_rc
            case 0
                if cd $_cc_target[-1]
                    set _cc_wt_slot (cc-worktree current --path $_cc_target[-1])
                else
                    echo "cc-worktree: cannot cd into $_cc_target[-1]; running un-isolated" >&2
                end
            case 2
                # Not opted in. The common case: one process, no output, and
                # `create` makes no git/jj call at all on this path.
            case '*'
                # Every slot held, or a backend failure. `create` has already
                # explained on stderr; running un-isolated beats refusing to
                # start, but it must never be silent.
                echo "cc-worktree: running WITHOUT isolation in $_cc_orig_pwd" >&2
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
    # _cc_worktree_key, not pwd: inside a slot every session would otherwise
    # read as "w-01" in Activity Monitor. The slot is appended instead, so the
    # label still says which one this is.
    set -l label (basename (_cc_worktree_key))
    if test -n "$_cc_wt_slot"
        set label "$label $_cc_wt_slot"
    end
    if test -n "$process_label"
        set label "$label @ $process_label $timestamp"
    else
        set label "$label $timestamp"
    end

    # Claude Code mangles '.' and ':' as well as '/' (~/.claude -> --claude), so
    # replacing only '/' silently pointed at a directory that never exists —
    # which made the post-session review below a no-op for any dotted path,
    # including every .alt/worktrees checkout.
    #
    # This MUST stay after the isolation cd: Claude Code derives its project
    # directory from the real cwd, so computing it from the parent would point
    # at a directory the isolated session never writes — the same silent no-op
    # the comment above records having been burned by.
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

    # --- isolation exit path ----------------------------------------------
    # cd back FIRST: `cc-worktree finish` resolves the repo from the cwd and
    # refuses to operate from inside a slot, and the agent in the worktree
    # cannot merge its own branch anyway (`fatal: 'master' is already checked
    # out`). Everything below then runs in the parent again.
    if test -n "$_cc_wt_slot"
        cd $_cc_orig_pwd
        cc-worktree finish --slot $_cc_wt_slot
    end

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
            # Keyed like every other ccs site, so an isolated session's backup
            # is found where _ccs_backup_session actually wrote it.
            set -l _ccs_dir "$HOME/Cloud/cc-sessions"(_cc_worktree_key)
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
