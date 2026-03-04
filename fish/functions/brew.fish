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

function _brew_claude_release_notes --description 'Summarize Claude Code release notes after upgrade' --argument-names old_ver new_ver
    echo
    echo (set_color brblack)"─── dotfiles/brew ───"(set_color normal)
    echo "Claude Code upgraded: $old_ver → $new_ver"
    echo "Fetching release notes..."

    set -l notes_file (mktemp /tmp/claude-release-notes.XXXXXX)
    claude -p '/release-notes' > "$notes_file" 2>/dev/null

    if test -s "$notes_file"
        echo "Summarizing..."
        echo
        claude -p "Summarize the changes from version $old_ver to $new_ver. Be concise — bullet points, grouped by theme. Skip anything outside that version range. At the end, add a '## Highlights' section with a 1-2 paragraph high-level summary of the most important changes for someone who just wants the headlines." < "$notes_file"
    else
        echo "Could not fetch release notes."
    end

    rm -f "$notes_file"
end

function brew --description 'Homebrew with update prompts' --wraps brew
    # For upgrade commands, capture output to detect "already installed" message
    if test "$argv[1]" = "upgrade"; and test (count $argv) -gt 1; and isatty stdout
        # Capture pre-upgrade claude version if upgrading claude-code
        set -l old_claude_ver
        if contains -- claude-code $argv
            set old_claude_ver (claude --version 2>/dev/null | awk '{print $1}')
        end

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

        # After successful claude-code upgrade, show release notes
        if test $brew_status -eq 0; and test -n "$old_claude_ver"
            set -l new_claude_ver (claude --version 2>/dev/null | awk '{print $1}')
            if test -n "$new_claude_ver"; and test "$old_claude_ver" != "$new_claude_ver"
                _brew_claude_release_notes "$old_claude_ver" "$new_claude_ver"
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
