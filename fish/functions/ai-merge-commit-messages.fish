function ai-merge-commit-messages --description 'Merge chunk commit messages into one cohesive message'
    argparse 'v/verbose' -- $argv
    or return 1

    set -l messages_file $argv[1]
    set -l messages_text (cat $messages_file)

    set -l prompt "Merge these commit message sections into one cohesive commit message.
- First line: 50 char max summary covering all changes
- Body: organized summary of all changes
- Keep it concise, no redundancy
- Output plain text only, no markdown

Sections:
$messages_text"

    if set -q _flag_verbose
        echo "    Merging "(grep -c '\-\-\-CHUNK\-\-\-' $messages_file)" chunk messages..." >&2
    end

    # See ai-chunk-files.fish for why the exit status alone can't be trusted here.
    set -l model claude-sonnet-5

    # The prompt here is only the chunk messages, so claude-p's 180s default is plenty.
    set -l rawfile (mktemp)
    claude-p --model $model "$prompt" >$rawfile
    set -l status_code $status
    set -l result (cat $rawfile | string collect)
    rm -f $rawfile

    if test $status_code -eq 124
        echo "ai-merge-commit-messages: claude timed out" >&2
        return 1
    end
    if test $status_code -ne 0
        echo "ai-merge-commit-messages: claude exited $status_code" >&2
        echo "  $result" >&2
        return 1
    end
    # claude-p already rejects an empty result and a model claude itself errors on, but
    # both checks stay: what it cannot catch is output claude was happy with and we are
    # not -- a leaked roleplay bookend arrives as a perfectly successful call.
    if not string match -qr '\S' -- "$result"
        echo "ai-merge-commit-messages: claude returned empty output" >&2
        return 1
    end
    if string match -qr 'was retired on|may not exist' -- "$result"
        echo "ai-merge-commit-messages: claude reported a model problem for '$model'" >&2
        echo "  "(string sub -l 200 "$result") >&2
        return 1
    end

    printf '%s\n' $result
end
