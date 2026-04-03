function ai-git-commit-chunked --description 'Generate commit message via chunking for large diffs'
    argparse 'v/verbose' -- $argv
    or return 1

    set -l chunk_budget 40000  # tokens per chunk target

    # Step 1: Build file manifest with token counts
    if set -q _flag_verbose
        echo "[1/4] Building file manifest..." >&2
    end
    set -l manifest
    set -l total_tokens 0
    for file in (git diff --staged --name-only)
        set -l chars (git diff --staged -- "$file" | wc -c | string trim)
        set -l tokens (math "ceil($chars / 4)")  # ~4 chars per token
        set total_tokens (math "$total_tokens + $tokens")
        set -l entry (printf '%s\t%s' "$file" "$tokens")
        set -a manifest "$entry"
        if set -q _flag_verbose
            echo "  $file: ~$tokens tokens" >&2
        end
    end
    if set -q _flag_verbose
        echo "DEBUG: manifest[1] = '$manifest[1]'" >&2
        echo "DEBUG: manifest[2] = '$manifest[2]'" >&2
    end
    if set -q _flag_verbose
        echo "  Total: ~$total_tokens tokens" >&2
    end

    # Step 2: AI groups files into chunks (Sonnet - fast/cheap)
    if set -q _flag_verbose
        echo "[2/4] AI grouping files into chunks (budget: $chunk_budget tokens/chunk)..." >&2
        echo "DEBUG: manifest has "(count $manifest)" entries" >&2
        echo "DEBUG: first entry: $manifest[1]" >&2
    end
    # Write manifest to temp file (piping doesn't work reliably)
    set -l manifest_file (mktemp)
    printf '%s\n' $manifest > $manifest_file
    if set -q _flag_verbose
        echo "DEBUG: wrote manifest to $manifest_file ("(wc -l < $manifest_file | string trim)" lines)" >&2
    end
    set -l chunk_args $chunk_budget $manifest_file
    set -q _flag_verbose; and set -a chunk_args --verbose
    set -l chunks (ai-chunk-files $chunk_args)
    rm -f $manifest_file
    echo "DEBUG: ai-chunk-files returned "(count $chunks)" chunks" >&2
    if set -q _flag_verbose
        echo "  Created "(count $chunks)" chunks:" >&2
        set -l i 0
        for chunk in $chunks
            test -z "$chunk"; and continue
            set i (math "$i + 1")
            echo "  Chunk $i: $chunk" >&2
        end
    end

    # Step 3: Generate message per chunk
    if set -q _flag_verbose
        echo "[3/4] Generating commit messages per chunk..." >&2
    end
    set -l messages
    set -l i 0
    for chunk in $chunks
        test -z "$chunk"; and continue
        set i (math "$i + 1")
        set -l files (string split ',' "$chunk")
        set -l chunk_diff (git diff --staged -- $files | string collect)
        if set -q _flag_verbose
            set -l chunk_chars (string length "$chunk_diff")
            echo "  Chunk $i: $chunk_chars chars -> AI..." >&2
        end
        set -l chunk_json (printf '%s' "$chunk_diff" | ai_write_git_commit | string collect)
        set -l msg (printf '%s' "$chunk_json" | jq -r .message)
        set -a messages "---CHUNK---" "$msg"
        if set -q _flag_verbose
            echo "  Chunk $i message:" >&2
            printf '%s\n' "$msg" | sed 's/^/    /' >&2
        end
    end

    # Step 4: Merge messages (Sonnet - fast/cheap)
    if set -q _flag_verbose
        echo "[4/4] Merging chunk messages..." >&2
    end
    set -l messages_file (mktemp)
    printf '%s\n' $messages > $messages_file
    set -l merge_args $messages_file
    set -q _flag_verbose; and set -a merge_args --verbose
    set -l final_message (ai-merge-commit-messages $merge_args)
    rm -f $messages_file
    # Output JSON to match ai_write_git_commit contract
    printf '%s' "$final_message" | jq -Rs '{message: .}'
end
