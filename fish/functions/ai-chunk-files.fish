function ai-chunk-files --description 'AI groups files into optimal chunks for commit messages'
    argparse 'v/verbose' -- $argv
    or return 1

    set -l budget $argv[1]
    set -l manifest_file $argv[2]
    set -l input (cat $manifest_file)

    set -l file_count (printf '%s\n' "$input" | wc -l | string trim)

    if set -q _flag_verbose
        echo "    Reading manifest from $manifest_file ($file_count files)" >&2
    end

    set -l input_text (printf '%s\n' $input | string collect)
    set -l prompt "Group these files into chunks for git commit messages.
Goals:
1. Keep semantically related files together (same feature/fix)
2. Each chunk should be under $budget tokens total
3. Minimize number of chunks

Input format: filename<tab>token_count
Output format: JSON array of arrays. Each inner array is a chunk containing filenames.
Example: [[\"file1.md\",\"file2.md\"],[\"file3.md\"]]

IMPORTANT: Output ONLY valid JSON. No explanation, no markdown code blocks.

Files:
$input_text"

    if set -q _flag_verbose
        echo "    Sending $file_count files to Sonnet for chunking..." >&2
        echo "    Prompt length: "(string length "$prompt")" chars" >&2
        echo "    Calling claude CLI..." >&2
    end

    # Model IDs also live in ai-merge-commit-messages.fish and dotfiles/bin/ai-commit-msg.
    # `claude-sonnet-4-20250514` sat here until 2026-07-28, six weeks after it was
    # retired (2026-06-15) -- see the exit-status warning below for why nothing noticed.
    set -l model claude-sonnet-5

    # Capture claude's OWN status. `set -l x ($cmd)` records the status of the `set`
    # builtin, not of $cmd, so the old `set -l status_code $status` on the following
    # line always read 0. Redirect to a file and read $status immediately instead.
    set -l rawfile (mktemp)
    claude -p --model $model "$prompt" >$rawfile
    set -l status_code $status
    set -l result (cat $rawfile | string collect)
    rm -f $rawfile

    if set -q _flag_verbose
        echo "    Claude returned (status: $status_code)" >&2
        echo "    Raw JSON: "(string sub -l 100 "$result")"..." >&2
    end

    # The exit status is NOT sufficient on its own: `claude -p --model <retired-id>`
    # prints "⚠ ... was retired on ..." to stdout and still exits 0. Validate the
    # shape of the output, or a dead model looks exactly like a successful call and
    # the caller silently produces no chunks.
    if test $status_code -ne 0
        echo "ai-chunk-files: claude exited $status_code" >&2
        echo "  $result" >&2
        return 1
    end
    if not printf '%s' "$result" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1
        echo "ai-chunk-files: claude did not return a non-empty JSON array (model '$model' retired or unavailable?)" >&2
        echo "  "(string sub -l 200 "$result") >&2
        return 1
    end

    # Parse JSON: convert each chunk array to comma-separated filenames
    printf '%s' "$result" | jq -r '.[] | join(",")'
end
