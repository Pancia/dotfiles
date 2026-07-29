function ai-git-commit-chunked --description 'Generate commit message via chunking for large diffs (git or jj)'
    argparse 'v/verbose' 'vcs=' 'paths=+' -- $argv
    or return 1

    set -l vcs git
    set -q _flag_vcs; and set vcs $_flag_vcs
    if not contains -- $vcs git jj
        echo "ai-git-commit-chunked: --vcs must be 'git' or 'jj' (got '$vcs')" >&2
        return 1
    end

    set -l chunk_budget 40000  # tokens per chunk target

    # Step 1: Build file manifest with token counts
    if set -q _flag_verbose
        echo "[1/4] Building file manifest ($vcs)..." >&2
    end
    # --paths scopes the manifest to a fileset expression (jj only). Without it,
    # a caller that scoped its own diff would still get a message describing
    # every file in the working copy, including paths it deliberately held back.
    set -l file_list
    if test "$vcs" = jj
        if set -q _flag_paths
            set file_list (jj diff --name-only -- $_flag_paths)
        else
            set file_list (jj diff --name-only)
        end
    else
        set file_list (git diff --staged --name-only)
    end
    set -l manifest
    set -l total_tokens 0
    for file in $file_list
        # jj parses paths after `--` as filesets, not literal paths; wrap as an
        # exact-file fileset so names with spaces/()/~ are handled (git uses pathspecs).
        set -l chars
        if test "$vcs" = jj
            set chars (jj diff -- "file:\"$file\"" | wc -c | string trim)
        else
            set chars (git diff --staged -- "$file" | wc -c | string trim)
        end
        set -l tokens (math "ceil($chars / 4)")  # ~4 chars per token
        set total_tokens (math "$total_tokens + $tokens")
        set -l entry (printf '%s\t%s' "$file" "$tokens")
        set -a manifest "$entry"
        if set -q _flag_verbose
            echo "  $file: ~$tokens tokens" >&2
        end
    end
    if set -q _flag_verbose
        echo "  Total: ~$total_tokens tokens across "(count $manifest)" files" >&2
    end

    # Step 2: AI groups files into chunks (Sonnet - fast/cheap)
    if set -q _flag_verbose
        echo "[2/4] AI grouping files into chunks (budget: $chunk_budget tokens/chunk)..." >&2
    end
    # Write manifest to temp file (piping doesn't work reliably)
    set -l manifest_file (mktemp)
    printf '%s\n' $manifest > $manifest_file
    set -l chunk_args $chunk_budget $manifest_file
    set -q _flag_verbose; and set -a chunk_args --verbose
    set -l chunks (ai-chunk-files $chunk_args)
    rm -f $manifest_file

    # Drop empty entries; fail fast if chunking produced nothing usable
    set -l real_chunks
    for chunk in $chunks
        test -z "$chunk"; and continue
        set -a real_chunks "$chunk"
    end
    if test (count $real_chunks) -eq 0
        echo "ai-git-commit-chunked: chunking produced no file groups" >&2
        echo '{"message": ""}'
        return 1
    end
    if set -q _flag_verbose
        echo "  Created "(count $real_chunks)" chunks:" >&2
        set -l i 0
        for chunk in $real_chunks
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
    for chunk in $real_chunks
        set i (math "$i + 1")
        set -l files (string split ',' "$chunk")
        set -l chunk_diff
        if test "$vcs" = jj
            set -l dargs
            for f in $files
                set -a dargs "file:\"$f\""
            end
            set chunk_diff (jj diff -- $dargs | string collect)
        else
            set chunk_diff (git diff --staged -- $files | string collect)
        end
        if set -q _flag_verbose
            echo "  Chunk $i: "(string length "$chunk_diff")" chars -> AI..." >&2
        end
        set -l chunk_jsonfile (mktemp)
        printf '%s' "$chunk_diff" | ai_write_git_commit > $chunk_jsonfile
        set -l chunk_status $pipestatus[2]
        set -l msg (jq -r '.message // empty' < $chunk_jsonfile | string collect)
        rm -f $chunk_jsonfile
        if test $chunk_status -ne 0; or not string match -qr '\S' -- "$msg"
            echo "ai-git-commit-chunked: chunk $i message generation failed" >&2
            echo '{"message": ""}'
            return 1
        end
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
    set -l final_message (ai-merge-commit-messages $merge_args | string collect)
    rm -f $messages_file
    if not string match -qr '\S' -- "$final_message"
        echo "ai-git-commit-chunked: merging chunk messages produced empty output" >&2
        echo '{"message": ""}'
        return 1
    end
    # Output JSON to match ai_write_git_commit contract
    printf '%s' "$final_message" | jq -Rs '{message: .}'
end
