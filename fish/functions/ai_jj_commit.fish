# Commit a jj change with an AI-generated message.
#
# Two modes:
#
#   ai_jj_commit [--no-edit]
#       Legacy/interactive: describes the ENTIRE working copy and commits it.
#       This is what `g run ci` uses.
#
#   ai_jj_commit --no-edit --paths-from FILE
#       Automated/scoped: commits ONLY the paths listed in FILE via `jj split`,
#       leaving everything else in the working copy. Used by Inari's 05:00 dream
#       job and the weekly review.
#
# Exit codes (consumed by tools/inari/inari.py):
#   0  committed
#   1  failed        -- message generation or a jj command failed
#   2  nothing       -- no changes in scope; NOT an error, do not retry
#   3  misconfigured -- allowlist missing/unreadable/empty; do not retry
#   4  locked        -- another commit is in progress; do not retry immediately
#   5  unclaimed     -- this session has Bash-window changes nobody has claimed;
#                       `ccjj claim` them and re-run for ONE commit, or pass
#                       --no-claim to commit without them. Agent-only: the
#                       session-scoped path requires CLAUDE_SESSION_ID.
#
# SAFETY INVARIANT: `--paths-from` must never degrade into committing everything.
# An allowlist that resolves to zero entries is a hard error (3), not a fallback.
# Passing zero filesets to `jj split` would also make it interactive (jj treats
# an empty path list as `--interactive`), which under launchd means a TUI against
# a pipe. Both failure modes are closed off in __ai_jj_commit_run.

function ai_jj_commit --description 'Commit jj change with AI-generated message (whole working copy, or path-scoped split)'
    # --dry-run mutates nothing, so it neither takes nor waits on the lock.
    if contains -- --dry-run $argv; or contains -- -n $argv
        __ai_jj_commit_run $argv
        return $status
    end

    # Route to a session-scoped commit when another live Claude session is
    # working in this repo: a whole-working-copy commit would capture its
    # half-written files. `ccjj should-scope` owns the decision so the rule lives
    # in one place, and it declines when this is the only session -- a whole-copy
    # commit is better then, because it also catches Bash-made changes that ccjj
    # cannot see.
    #
    # Deliberately BEFORE the lock: ccjj takes this same lockdir, so delegating
    # while holding it would make the tool deadlock against itself and return 4.
    if set -q CLAUDE_SESSION_ID; and not string match -q -- '--paths-from*' $argv
        if ccjj should-scope -q 2>/dev/null
            __ai_jj_commit_run --session $argv
            return $status
        end
    end

    set -l repo_root (jj root 2>/dev/null)
    if test -z "$repo_root"
        echo "ai_jj_commit: not inside a jj repo" >&2
        return 1
    end

    # Advisory lock. The 05:00 job and a manual `g run ci` would otherwise each
    # snapshot, spend ~30s in the LLM, then mutate an `@` that has moved. The
    # backup hook is the part that actually breaks: `git bundle create` takes
    # <path>.lock with LOCK_DIE_ON_ERROR, so one of two concurrent runs dies.
    set -l lock_base "$HOME/.local/state/ai-jj-commit"
    if not mkdir -p "$lock_base" 2>/dev/null
        # A permanent configuration problem (unwritable ~/.local/state) must not be
        # reported as "locked" -- `locked` is deliberately not retried, so it would
        # silently skip every night forever.
        echo "ai_jj_commit: cannot create lock directory $lock_base" >&2
        return 1
    end
    set -l lockdir "$lock_base/"(string replace -a / _ -- $repo_root)".lock"

    if not mkdir "$lockdir" 2>/dev/null
        set -l holder (cat "$lockdir/pid" 2>/dev/null | string trim)

        if test -z "$holder"
            # The lockdir exists but carries no pid yet: another process is between
            # its mkdir and its pid write. Backing off is correct -- treating this as
            # stale and stealing the lock is exactly the interleaving the lock exists
            # to prevent. The age check keeps a genuinely orphaned empty lockdir from
            # wedging the job permanently.
            if test (find "$lockdir" -maxdepth 0 -mmin +30 2>/dev/null | count) -eq 0
                echo "ai_jj_commit: lock is being acquired by another process" >&2
                return 4
            end
            echo "ai_jj_commit: clearing abandoned lock with no pid file" >&2
            rm -rf "$lockdir"
        else
            # Identity is pid + process start time. `kill -0 $pid` alone only proves
            # SOME process holds that pid -- after a SIGKILL from the commit timeout,
            # a recycled pid would look alive forever and every later night would
            # return 4 and skip.
            set -l holder_pid (string split ' ' -- $holder)[1]
            set -l holder_start (string join ' ' (string split ' ' -- $holder)[2..-1])
            set -l live_start (ps -o lstart= -p $holder_pid 2>/dev/null | string trim)

            if test -n "$live_start"; and test "$live_start" = "$holder_start"
                echo "ai_jj_commit: another commit is in progress (pid $holder_pid)" >&2
                return 4
            end
            # Holder is gone, or its pid was recycled by an unrelated process.
            echo "ai_jj_commit: clearing stale lock (pid $holder_pid)" >&2
            rm -rf "$lockdir"
        end

        if not mkdir "$lockdir" 2>/dev/null
            echo "ai_jj_commit: could not acquire lock at $lockdir" >&2
            return 4
        end
    end
    printf '%s %s\n' $fish_pid (ps -o lstart= -p $fish_pid 2>/dev/null | string trim) >"$lockdir/pid"

    __ai_jj_commit_run $argv
    set -l rc $status
    rm -rf "$lockdir"
    return $rc
end

function __ai_jj_commit_run --description 'ai_jj_commit implementation (assumes lock is held)'
    argparse 'n/dry-run' 'v/verbose' 'no-edit' 'paths-from=' 'session' 'no-claim' -- $argv
    or return 1

    # Declared at function level: `set -l` is function-scoped, not block-scoped,
    # so a variable assigned only inside an if-branch is undefined when the
    # branch isn't taken.
    set -l scoped 0
    set -l selector ""
    set -l entries
    set -l session 0
    if set -q _flag_session
        set session 1
    end

    if set -q _flag_paths_from
        set scoped 1

        if not test -r "$_flag_paths_from"
            echo "ai_jj_commit: allowlist file not readable: $_flag_paths_from" >&2
            return 3
        end

        for line in (cat "$_flag_paths_from")
            # Strip a BOM before trimming: U+FEFF is a format char, not
            # whitespace, so `string trim` leaves it in place and the entry
            # silently matches nothing -- the allowlisted dir would just quietly
            # stop being committed while everything still reported success.
            set -l entry (string replace -a ﻿ '' -- $line | string trim)
            test -z "$entry"; and continue
            string match -q '#*' -- $entry; and continue
            # Entries are interpolated into root:"<entry>". `"` and `\` would
            # break out of that quoting and change the fileset's meaning. `#`
            # almost always means a trailing inline comment, which is NOT
            # supported: `memories # only the good ones` would become one entry
            # matching nothing. Everything else (: & | ~ spaces) is inert once
            # quoted. This set must stay identical to inari.py's
            # _ILLEGAL_ENTRY_CHARS -- the two parsers read the same file.
            if string match -qr '["\\\\#]' -- $entry
                echo "ai_jj_commit: illegal character in allowlist entry: $entry" >&2
                echo "ai_jj_commit: (inline # comments are not supported; use a whole-line comment)" >&2
                return 3
            end
            # Whitespace that isn't a plain space. `string trim` leaves these in
            # place while Python's str.strip() would remove them, so accepting one
            # here means the committer and the notification disagree about the
            # entry -- the directory silently stops being committed AND is omitted
            # from the held-back list. macOS types U+00A0 for Option+Space, and
            # pasting a path out of rendered markdown or a PDF produces them.
            if string match -qr '\x{a0}|\x0b|\x0c|\x{2028}|\x{2029}|\x{202f}|\x{3000}' -- $entry
                echo "ai_jj_commit: non-plain whitespace in allowlist entry: $entry" >&2
                echo "ai_jj_commit: (retype it -- a pasted path often carries a non-breaking space)" >&2
                return 3
            end
            set -a entries "root:\"$entry\""
        end

        if test (count $entries) -eq 0
            echo "ai_jj_commit: allowlist '$_flag_paths_from' yielded no entries; refusing to fall back to committing the whole working copy" >&2
            return 3
        end

        # `root:` makes every entry root-relative, so the caller's cwd is
        # irrelevant. A bare fileset is a CWD-relative prefix-glob, which would
        # silently match nothing when invoked from a subdirectory and report the
        # repo as clean.
        set selector (string join '|' $entries)
        if set -q _flag_verbose
            echo "Scoped to "(count $entries)" allowlist entries" >&2
        end
    end

    # Capture jj's own exit status. `set -l diff (jj diff ...)` records the status of
    # the `set` builtin, so a FAILING jj diff -- a stale working copy, a concurrent
    # operation, an unreadable .jj -- writes its error to stderr, produces EMPTY
    # stdout, and would sail into the emptiness check below as "nothing to commit":
    # exit 2, no retry, and _commit_note() renders nothing, so the 05:00 job would
    # go silent every night until someone ran `jj status` by hand. Note
    # `snapshot.auto-update-stale = false` in this repo deliberately enables that
    # error path. Redirect to a file so $status is jj's.
    set -l difffile (mktemp)
    if test $session -eq 1
        # The RECONSTRUCTED diff, not `jj diff`. For a file two sessions both
        # touched, `jj diff` carries the other session's hunks too, so the
        # generated message would describe work that is not being committed.
        if set -q _flag_no_claim
            ccjj commit --diff --no-claim >$difffile
        else
            ccjj commit --diff >$difffile
        end
    else if test $scoped -eq 1
        jj diff -- "$selector" >$difffile
    else
        jj diff >$difffile
    end
    set -l jj_status $status
    set -l diff (cat $difffile | string collect)
    rm -f $difffile

    # 5 means this session has Bash-window changes nobody has claimed. ccjj has
    # already printed them and the exact `ccjj claim` lines. Stop HERE, before
    # spending a model call on a message and before committing: claiming then
    # re-running yields one commit instead of two. Only reachable under an
    # agent -- the routing above requires CLAUDE_SESSION_ID -- so a human's
    # `g run ci` never sees this.
    if test $jj_status -eq 5
        echo "ai_jj_commit: stopped before committing; claim the paths above and re-run" >&2
        echo "              (or: ai_jj_commit --no-claim ... to commit without them)" >&2
        return 5
    end

    if test $jj_status -ne 0
        echo "ai_jj_commit: jj diff failed (exit $jj_status); working copy stale or repo busy" >&2
        return 1
    end

    set -l diff_len (string length "$diff")
    # ~100k tokens. jj has no staging area, so this measures the whole working
    # copy; chunking therefore triggers more readily than the staged-only git path.
    set -l max_len (math "100000 * 4")

    # THE EMPTINESS ORACLE. This must test the SCOPED diff. If it ever reverts to
    # a bare `jj diff`, then a retry after a successful split -- where the working
    # copy holds only the deliberately-held-back code -- would see "changes exist",
    # regenerate a message, and commit that code under a journal-flavoured
    # description. That is the one-line difference between safe and catastrophic.
    if test $diff_len -eq 0
        if test $scoped -eq 1
            echo "ai_jj_commit: no changes in allowlisted paths" >&2
        else if test $session -eq 1
            echo "ai_jj_commit: this session recorded no committable changes" >&2
            echo "ai_jj_commit: (other sessions' work is still in the working copy; `ccjj audit`)" >&2
        else
            echo "ai_jj_commit: no changes in working copy" >&2
        end
        return 2
    end

    if set -q _flag_verbose
        echo "Diff: $diff_len chars" >&2
    end

    # Generate the message: chunk large diffs, else single-pass. Both branches
    # write raw JSON to $msgfile so the generator's exit status is observable —
    # capture it on the very next line (any later command clobbers $pipestatus).
    set -l msgfile (mktemp)
    set -l gen_status
    if test $diff_len -gt $max_len
        set -q _flag_verbose; and echo "Using chunked pipeline (threshold: $max_len)" >&2
        set -l chunked_args --vcs jj
        set -q _flag_verbose; and set -a chunked_args --verbose
        # Without this the chunked branch rebuilds its manifest from an
        # unfiltered `jj diff --name-only` and describes the held-back code too.
        test $scoped -eq 1; and set -a chunked_args --paths "$selector"
        ai-git-commit-chunked $chunked_args >$msgfile
        set gen_status $status
    else
        set -q _flag_verbose; and echo "Using single-pass pipeline" >&2
        printf '%s' "$diff" | ai_write_git_commit >$msgfile
        set gen_status $pipestatus[2]
    end

    set -l message (jq -r '.message // empty' <$msgfile | string collect)
    rm -f $msgfile

    # Fail fast: never touch jj if generation failed or produced an empty message.
    # `string match -qr '\S'` is true only when the message has a non-whitespace
    # char; avoids the command-substitution splitting that breaks `test -z` on
    # multi-line messages.
    if test $gen_status -ne 0; or not string match -qr '\S' -- "$message"
        echo "ai_jj_commit: commit message generation failed" >&2
        return 1
    end

    if set -q _flag_dry_run
        echo "--- DRY RUN ---" >&2
        printf '%s\n' "$message"
        return 0
    end

    if test $scoped -eq 1
        # ALWAYS split. There is deliberately no "everything matched, so just
        # describe" fallback: `jj describe` would run against the unfiltered
        # working copy, and the branch decision would come from a probe taken
        # ~30s earlier (before the LLM call), so anything saved during that
        # window would be committed *because the probe said journal-only*.
        #
        # jj handles a full selection natively -- it warns "All changes have been
        # selected, so the original revision will become empty" and produces
        # journal-commit + empty @, i.e. exactly describe+new, atomically.
        #
        # After the split, @ is the REMAINDER (jj moves the working copy to the
        # second commit), so held-back edits stay exactly where they were.
        if not jj split -m "$message" -- "$selector"
            echo "ai_jj_commit: jj split failed" >&2
            return 1
        end
    else if test $session -eq 1
        # ccjj takes the shared lock itself, verifies the commit landed, and
        # reports any working-copy paths no session claimed.
        if set -q _flag_no_claim
            ccjj commit -m "$message" --no-claim
        else
            ccjj commit -m "$message"
        end
        set -l rc $status
        if test $rc -ne 0
            return $rc
        end
    else
        jj describe -m "$message"; or return 1
        if set -q _flag_no_edit
            jj new; or return 1
        else
            jj commit; or return 1
        end
        # Every session's claims are now in history. Leaving the journals live
        # would make their paths look permanently claimed and wedge the nudge on.
        ccjj retire-all -q 2>/dev/null
    end

    printf '%s\n' "$message"
end
