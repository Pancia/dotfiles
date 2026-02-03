function ai_git_commit --description 'Commit with AI-generated message'
    argparse 'n/dry-run' 'v/verbose' -- $argv
    or return 1

    set -l diff (git diff --staged | string collect)
    set -l diff_len (string length "$diff")
    set -l max_len (math "100000 * 4")  # ~100k tokens
    set -l message

    if set -q _flag_verbose
        echo "Staged diff: $diff_len chars" >&2
    end

    if test $diff_len -gt $max_len
        # Large diff: use chunking pipeline
        if set -q _flag_verbose
            echo "Using chunked pipeline (threshold: $max_len)" >&2
        end
        set -l chunked_args
        set -q _flag_verbose; and set -a chunked_args --verbose
        set message (_ai_git_commit_chunked $chunked_args | string collect)
    else
        # Normal: use full diff
        if set -q _flag_verbose
            echo "Using single-pass pipeline" >&2
        end
        set message (printf '%s' "$diff" | ai_write_git_commit | string collect)
    end

    if set -q _flag_dry_run
        echo "--- DRY RUN ---" >&2
        echo "$message"
    else
        git commit --edit -m "$message"
    end
end
