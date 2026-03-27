function ccu --description 'Check Claude Code updates, show release notes, prompt to install'
    set -l current_ver (claude --version 2>/dev/null | awk '{print $1}')
    if test -z "$current_ver"
        echo "Could not determine current Claude version"
        return 1
    end

    set -l latest_ver (gh release view -R anthropics/claude-code --json tagName -q .tagName 2>/dev/null | string replace -r '^v' '')
    if test -z "$latest_ver"
        echo "Could not fetch latest release from GitHub"
        return 1
    end

    if test "$current_ver" = "$latest_ver"
        echo "Claude Code is up to date ($current_ver)"
        return 0
    end

    _claude_release_notes "$current_ver" "$latest_ver"

    echo
    read -P "Update $current_ver → $latest_ver? [y/N] " -n 1 response
    or return
    if string match -qi 'y' "$response"
        claude update
    end
end
