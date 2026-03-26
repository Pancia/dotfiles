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

    # Sync project skills/agents/commands from .cc-config (or default group)
    if test -f .cc-config
        set -l cc_hash (md5 -q .cc-config)
        set -l stamp .claude/.cc-sync-stamp
        if not test -f $stamp; or test "$cc_hash" != (cat $stamp)
            set -l cc_profile (string match -v '//*' < .cc-config | string trim)
            if test -n "$cc_profile"
                cc-config sync $cc_profile
                echo $cc_hash > $stamp
            end
        end
    else if test -d .claude
        set -l config_file ~/dotfiles/ai/cc-config.json
        set -l default_group (jq -r '.default // empty' $config_file)
        if test -n "$default_group"
            set -l stamp .claude/.cc-sync-stamp
            if not test -f $stamp; or test "default:$default_group" != (cat $stamp)
                cc-config sync $default_group
                echo "default:$default_group" > $stamp
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
    # Skip post-session review for non-interactive invocations
    set -l skip_review 0
    if contains -- -p $pass_argv; or contains -- --print $pass_argv
        set skip_review 1
    end

    # Snapshot the most recent session JSONL before running
    set -l sessions_dir "$HOME/.claude/projects/"(string replace -a '/' '-' (pwd))
    set -l pre_latest
    if test -d "$sessions_dir"
        set pre_latest (ls -t "$sessions_dir"/*.jsonl 2>/dev/null | head -1)
    end

    proc-label "claude [$label]" claude --verbose $pass_argv

    # Post-session review: find the session JSONL and review in background
    if test $skip_review -eq 0; and test -d "$sessions_dir"
        set -l post_latest (ls -t "$sessions_dir"/*.jsonl 2>/dev/null | head -1)
        if test -n "$post_latest"
            echo "📋 Reviewing session for CLAUDE.md updates (background)..."
            fish -c "cc-session-review '$post_latest'" &>/dev/null &
            disown
        end
    end
end
