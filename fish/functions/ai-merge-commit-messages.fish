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

    set -l result (claude -p --model claude-sonnet-4-20250514 "$prompt")
    printf '%s\n' $result
end
