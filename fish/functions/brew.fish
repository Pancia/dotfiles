function _brew_should_prompt_update --description 'Check if 1 day passed since last brew update'
    set -l lock_file "$HOME/.cache/dotfiles/cache/brew_update.glock"
    set -l interval_sec (math "1440 * 60")  # 1 day in seconds

    set -l now (date +%s)
    set -l last (cat "$lock_file" 2>/dev/null; or echo '0')
    set -l delta (math "$now - $last")

    test $delta -ge $interval_sec
end

function _brew_mark_updated --description 'Record brew update timestamp'
    set -l lock_file "$HOME/.cache/dotfiles/cache/brew_update.glock"
    mkdir -p (dirname "$lock_file")
    date +%s > "$lock_file"
end

function brew --description 'Homebrew with update prompts' --wraps brew
    # For upgrade commands, capture output to detect "already installed" message
    if test "$argv[1]" = "upgrade"; and test (count $argv) -gt 1; and isatty stdout
        set -l output (command brew $argv 2>&1)
        set -l brew_status $status
        echo -n "$output"

        # Check if we got the "already installed" message
        if string match -q "*the latest version is already installed*" "$output"
            echo
            echo (set_color brblack)"─── dotfiles/brew ───"(set_color normal)
            read -P "Run 'brew update' and retry upgrade? [y/N] " -n 1 response
            if string match -qi 'y' "$response"
                echo
                command brew update
                set -l update_status $status
                if test $update_status -eq 0
                    echo
                    command brew $argv
                    set brew_status $status
                end
                _brew_mark_updated
            end
        end
        return $brew_status
    end

    command brew $argv
    set -l brew_status $status

    # Only prompt in interactive shells after successful commands
    if test $brew_status -eq 0; and isatty stdout; and _brew_should_prompt_update
        # Check if homebrew-core has remote updates (without fetching)
        set -l tap_dir (command brew --repository homebrew/core 2>/dev/null)
        set -l has_updates (git -C "$tap_dir" fetch --dry-run 2>&1)
        if test -n "$has_updates"
            echo
            echo (set_color brblack)"─── dotfiles/brew ───"(set_color normal)
            read -P "brew update available. Run it? [y/N] " -n 1 response
            if string match -qi 'y' "$response"
                command brew update
            end
            _brew_mark_updated
        else
            _brew_mark_updated  # Already current, reset timer
        end
    end

    return $brew_status
end
