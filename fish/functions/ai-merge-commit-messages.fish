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

    set -l rawfile (mktemp)
    claude -p --model $model "$prompt" >$rawfile
    set -l status_code $status
    set -l result (cat $rawfile | string collect)
    rm -f $rawfile

    if test $status_code -ne 0
        echo "ai-merge-commit-messages: claude exited $status_code" >&2
        echo "  $result" >&2
        return 1
    end
    # A retired model prints its warning to stdout and exits 0, so an unvalidated
    # result would be committed as the message body.
    if not string match -qr '\S' -- "$result"
        echo "ai-merge-commit-messages: claude returned empty output (model '$model' retired or unavailable?)" >&2
        return 1
    end
    if string match -qr 'was retired on|may not exist' -- "$result"
        echo "ai-merge-commit-messages: claude reported a model problem for '$model'" >&2
        echo "  "(string sub -l 200 "$result") >&2
        return 1
    end

    printf '%s\n' $result
end
