function ai_git_commit --description 'Commit with AI-generated message'
    argparse 'n/dry-run' 'v/verbose' -- $argv
    or return 1

    set -l diff (git diff --staged | string collect)
    set -l diff_len (string length "$diff")
    set -l max_len (math "100000 * 4")  # ~100k tokens

    if test $diff_len -eq 0
        echo "No staged changes" >&2
        return 1
    end

    if set -q _flag_verbose
        echo "Staged diff: $diff_len chars" >&2
    end

    # Generate the message: chunk large diffs, else single-pass. Both branches
    # write raw JSON to $msgfile so the generator's exit status is observable —
    # capture it on the very next line (any later command clobbers $pipestatus).
    set -l msgfile (mktemp)
    set -l gen_status
    if test $diff_len -gt $max_len
        set -q _flag_verbose; and echo "Using chunked pipeline (threshold: $max_len)" >&2
        set -l chunked_args --vcs git
        set -q _flag_verbose; and set -a chunked_args --verbose
        ai-git-commit-chunked $chunked_args > $msgfile
        set gen_status $status
    else
        set -q _flag_verbose; and echo "Using single-pass pipeline" >&2
        printf '%s' "$diff" | ai_write_git_commit > $msgfile
        set gen_status $pipestatus[2]
    end

    set -l message (jq -r '.message // empty' < $msgfile | string collect)
    rm -f $msgfile

    # Fail fast: never commit if generation failed or produced an empty message.
    # `string match -qr '\S'` is true only when the message has a non-whitespace
    # char; avoids the command-substitution splitting that breaks `test -z` on
    # multi-line messages.
    if test $gen_status -ne 0; or not string match -qr '\S' -- "$message"
        echo "ai_git_commit: commit message generation failed" >&2
        return 1
    end

    if set -q _flag_dry_run
        echo "--- DRY RUN ---" >&2
        printf '%s\n' "$message"
        return 0
    end

    git commit --edit -m "$message"
    printf '%s\n' "$message"
end
