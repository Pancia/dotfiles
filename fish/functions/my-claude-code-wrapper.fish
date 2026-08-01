function my-claude-code-wrapper --description "Claude Code wrapper" --wraps claude
    # Extract --process-label manually to avoid argparse treating -p as abbreviation
    set -l process_label
    set -l pass_argv
    set -l skip_next 0
    # --no-worktree is ours, not claude's, so it is consumed here and never
    # forwarded (claude would reject it). It is matched BEFORE the
    # --process-label value branch deliberately: otherwise
    # `cc --process-label --no-worktree` takes it as the label text and the
    # opt-out silently does nothing, which is the worst outcome for a flag whose
    # entire job is to let the user say no.
    set -l no_worktree 0
    for arg in $argv
        if test "$arg" = --no-worktree
            set no_worktree 1
        else if test $skip_next -eq 1
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

    # --- per-session worktree ---------------------------------------------
    # In a repo opted in with `cc-worktree on`, hand Claude Code its own
    # `--worktree` so two sessions in one checkout cannot tread on each other.
    #
    # This used to be a bespoke implementation that created the worktree itself
    # and cd'd into it. Claude Code has done this natively since v2.1.49, and
    # doing it ourselves was what forced all the machinery that has now gone:
    # slots, holds, a reaper, and slot-aware resume all existed only because the
    # wrapper hid the worktree from Claude Code. It no longer does, so the
    # wrapper only appends a flag and never changes directory.
    #
    # NOTE the mode switch this creates: the new checkout is a *git* worktree
    # with no .jj of its own, so inside it `jj` resolves to the PARENT repo.
    # bin/cc-worktree-nudge warns the agent about that on every prompt.
    #
    # skip_extras gating is load-bearing: ai.fish, ai_health, ai_inbox, ccpu and
    # sanctuary/main-claude all route through this wrapper with -p, and would
    # otherwise leak a worktree per run AND get an empty checkout to inspect.
    #
    # ~/dotfiles cannot be isolated and is refused by `should-isolate` — there
    # the answer is ccjj / commit-mine, docs/cc-jj-sessions.md.
    set -l wt_flag
    # A resume already returns the session to the worktree it ran in (verified:
    # `claude --resume <id>` from the parent reaches it), so adding the flag
    # would strand it in a fresh empty one instead.
    if test $no_worktree -eq 0; and test $skip_extras -eq 0; and not __cc_resume_requested $pass_argv
        # An explicit worktree flag is the user's own choice and always wins.
        # `contains` cannot see the attached forms (`-wname`, `--worktree=x`),
        # hence the globs. Two separate patterns because they cannot be merged:
        # `-w*` does not match `--worktree` (that starts `--`), and `--worktree*`
        # does not match `-wname`.
        #
        # NOT '-w?*'. In fish 4 `?` is no longer a glob wildcard, so that pattern
        # matches nothing at all and `-wname` silently got a SECOND --worktree
        # appended. Verified: `string match -q -- 'x?*' xmine` returns 1.
        set -l wt_present 0
        for arg in $pass_argv
            if string match -q -- '-w*' $arg; or string match -q -- '--worktree*' $arg
                set wt_present 1
                break
            end
        end
        # A generated name, not a stable one: two concurrent sessions sharing a
        # default name would land in one worktree, which is the opposite of the
        # point. The pid disambiguates two starts within the same second.
        if test $wt_present -eq 0; and cc-worktree should-isolate
            set wt_flag --worktree "cc-"(date +%H%M%S)"-$fish_pid"
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
    # Plain pwd again: the wrapper no longer changes directory, so this is
    # always the repo the human launched from, which is the name worth seeing in
    # Activity Monitor. (It used to run through _cc_worktree_key because the
    # wrapper had already cd'd into a slot by this point and every session would
    # otherwise have read as "w-01".)
    set -l label (basename (pwd))
    if test -n "$process_label"
        set label "$label @ $process_label $timestamp"
    else
        set label "$label $timestamp"
    end

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

    proc-label "claude [$label]" claude --verbose $wt_flag $pass_argv

    # Claude Code derives its project directory from the cwd it actually ran in,
    # and --worktree makes it cd there AFTER this wrapper has launched it — so
    # pwd here is the parent while the transcript is keyed to the worktree.
    # Computing sessions_dir from pwd would point at a directory the session
    # never wrote and skip the review in silence: the same silent no-op the
    # comment below records having been burned by once already. Measured, not
    # assumed — the transcript lands under the mangled *worktree* path.
    #
    # ccsave-hook (SessionStart) records the real cwd into the ccs entry, which
    # is the only reliable source: the hook sees the cwd claude actually chose.
    # Fall back to pwd when there is no entry file (skip_extras) or the hook did
    # not run (--safe-mode disables hooks).
    set -l real_cwd (pwd)
    if test -n "$CCS_ENTRY_FILE"; and test -f "$CCS_ENTRY_FILE"
        set -l recorded (jq -r '.cwd // empty' "$CCS_ENTRY_FILE" 2>/dev/null)
        if test -n "$recorded"; and test -d "$recorded"
            set real_cwd $recorded
        end
    end
    # Claude Code mangles '.' and ':' as well as '/' (~/.claude -> --claude), so
    # replacing only '/' silently pointed at a directory that never exists —
    # which made the post-session review below a no-op for any dotted path,
    # including every .alt/worktrees checkout.
    set -l sessions_dir "$HOME/.claude/projects/"(string replace -a '/' '-' $real_cwd | string replace -a '.' '-' | string replace -a ':' '-')

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
