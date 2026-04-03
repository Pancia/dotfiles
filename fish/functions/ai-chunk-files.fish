function ai-chunk-files --description 'AI groups files into optimal chunks for commit messages'
    echo "DEBUG: ai-chunk-files called with argv: $argv" >&2

    argparse 'v/verbose' -- $argv
    or return 1

    echo "DEBUG: after argparse, argv: $argv, verbose: "(set -q _flag_verbose; and echo yes; or echo no) >&2

    set -l budget $argv[1]
    set -l manifest_file $argv[2]
    echo "DEBUG: reading from file $manifest_file" >&2
    set -l input (cat $manifest_file)
    echo "DEBUG: input has "(printf '%s\n' "$input" | wc -l | string trim)" lines" >&2

    set -l file_count (printf '%s\n' "$input" | wc -l | string trim)

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

    set -l result (claude -p --model claude-sonnet-4-20250514 "$prompt" | string collect)
    set -l status_code $status

    if set -q _flag_verbose
        echo "    Claude returned (status: $status_code)" >&2
        echo "    Raw JSON: "(string sub -l 100 "$result")"..." >&2
    end

    # Parse JSON: convert each chunk array to comma-separated filenames
    printf '%s' "$result" | jq -r '.[] | join(",")'
end
