function ai_jj_describe --description 'Describe current jj change with AI-generated message'
    argparse 'n/dry-run' 'v/verbose' -- $argv
    or return 1

    set -l diff (jj diff | string collect)
    set -l diff_len (string length "$diff")

    if test $diff_len -eq 0
        echo "No changes in working copy" >&2
        return 1
    end

    if set -q _flag_verbose
        echo "Diff: $diff_len chars" >&2
    end

    set -l message (printf '%s' "$diff" | ai_write_git_commit | string collect)

    if set -q _flag_dry_run
        echo "--- DRY RUN ---" >&2
        echo "$message"
    else
        jj describe -m "$message"
    end
end
