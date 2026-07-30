function _claude_release_notes --description 'Fetch and summarize Claude Code release notes' --argument-names old_ver new_ver
    echo
    echo (set_color brblack)"─── claude release notes ───"(set_color normal)
    echo "Claude Code: $old_ver → $new_ver"
    echo "Fetching release notes..."

    set -l notes
    set -l max_attempts 3
    for i in (seq $max_attempts)
        set notes (gh release view "v$new_ver" -R anthropics/claude-code --json body -q .body 2>/dev/null)
        if test -n "$notes"
            break
        end
        if test $i -lt $max_attempts
            echo "Release not published yet, retrying in 15s... ($i/$max_attempts)"
            sleep 15
        end
    end

    if test -z "$notes"
        echo "Release notes for $new_ver not available yet. Run: gh release view v$new_ver -R anthropics/claude-code"
        return 1
    end

    echo
    # `printf '%s\n' $notes`, not `echo "$notes"`: quoting the list joined the release
    # body onto one line. `--tools=''` keeps the summary about that body -- with tools on,
    # a thin body (v2.1.220's is two lines) sent claude off to read whatever repo it was
    # launched from instead. The `=` is required: `--tools <tools...>` is variadic, so a
    # space swallows the prompt as a tool name. And with no tools it has to be told that
    # stdin is all it gets, or it stops to go looking.
    printf '%s\n' $notes | claude-p --tools='' "The release body on stdin is the only input you have; summarize just what it says and nothing else. If it says little, say so briefly. Be concise — bullet points, grouped by theme. At the end, add a '## Highlights' section with a 1-2 paragraph high-level summary of the most important changes for someone who just wants the headlines."
    set -l rc $status
    if test $rc -ne 0
        # claude-p names the reason on stderr; the notes themselves are one command away,
        # same as when gh comes up empty above.
        if test $rc -eq 124
            echo "Summarizing timed out. Run: gh release view v$new_ver -R anthropics/claude-code"
        else
            echo "Could not summarize. Run: gh release view v$new_ver -R anthropics/claude-code"
        end
        return 1
    end
end
