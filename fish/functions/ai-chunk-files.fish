function ai-chunk-files --description 'AI groups files into optimal chunks for commit messages'
    argparse 'v/verbose' -- $argv
    or return 1

    set -l budget $argv[1]
    set -l manifest_file $argv[2]
    set -l input (cat $manifest_file)

    # count, not `wc -l`: quoting $input joined the manifest into one line, so the
    # verbose output claimed "1 files" for every manifest.
    set -l file_count (count $input)

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

Files:
$input_text"

    # The reply is constrained by this schema server-side, which is why the prompt
    # above no longer has to beg for "ONLY valid JSON, no markdown code blocks".
    #
    # It has to be an OBJECT with a `chunks` key rather than the bare array we
    # actually want: the API rejects a top-level array outright with
    # `input_schema.type: Input should be 'object'` (400). The wrapper is unwrapped
    # in the jq below.
    set -l chunk_schema '{"type":"object","properties":{"chunks":{"type":"array","description":"One inner array per chunk, each holding that chunk\'s filenames","items":{"type":"array","items":{"type":"string"}}}},"required":["chunks"],"additionalProperties":false}'

    if set -q _flag_verbose
        echo "    Sending $file_count files to Sonnet for chunking..." >&2
        echo "    Prompt length: "(string length "$prompt")" chars" >&2
        echo "    Calling claude CLI..." >&2
    end

    # Model IDs also live in ai-merge-commit-messages.fish and dotfiles/bin/ai-commit-msg.
    # `claude-sonnet-4-20250514` sat here until 2026-07-28, six weeks after it was
    # retired (2026-06-15) -- see the exit-status warning below for why nothing noticed.
    set -l model claude-sonnet-5

    # A whole-repo manifest is a few hundred lines of prompt, so give claude-p more
    # room than its 180s default before it kills the child.
    set -l timeout 300

    # Capture claude's OWN status. `set -l x ($cmd)` records the status of the `set`
    # builtin, not of $cmd, so the old `set -l status_code $status` on the following
    # line always read 0. Redirect to a file and read $status immediately instead.
    set -l rawfile (mktemp)
    CLAUDE_P_TIMEOUT=$timeout claude-p --model $model --json-schema "$chunk_schema" \
        "$prompt" >$rawfile
    set -l status_code $status
    set -l result (cat $rawfile | string collect)
    rm -f $rawfile

    if set -q _flag_verbose
        echo "    Claude returned (status: $status_code)" >&2
        echo "    Raw JSON: "(string sub -l 100 "$result")"..." >&2
    end

    # claude-p turns the errors claude reports with exit code 0 (a retired --model
    # among them) into a nonzero exit, so the status is worth checking -- and with
    # --json-schema and --safe-mode both in play, a clean exit now really does mean a
    # clean payload. The shape assertion below stays anyway: it is one jq call, it is
    # the thing that fails loudly if a schema is ever dropped from this call, and it
    # costs nothing. What changed is that it should no longer ever fire.
    if test $status_code -eq 124
        echo "ai-chunk-files: claude timed out after "$timeout"s" >&2
        return 1
    end
    if test $status_code -ne 0
        echo "ai-chunk-files: claude exited $status_code" >&2
        echo "  $result" >&2
        return 1
    end
    if not printf '%s' "$result" | jq -e '.chunks | type == "array" and length > 0' >/dev/null 2>&1
        echo "ai-chunk-files: claude did not return a non-empty chunks array" >&2
        echo "  "(string sub -l 200 "$result") >&2
        return 1
    end

    # Unwrap the schema's object and convert each chunk array to comma-separated
    # filenames
    printf '%s' "$result" | jq -r '.chunks[] | join(",")'
end
