function ai-merge-commit-messages --description 'Merge chunk commit messages into one cohesive message'
    argparse 'v/verbose' -- $argv
    or return 1

    set -l messages_file $argv[1]
    # `string collect`, or the capture becomes one list element per line and the
    # interpolation below space-joins them: every ---CHUNK--- boundary, summary/body
    # split and bullet list in the input was arriving as a single line, so the model
    # was merging sections it could no longer see as sections. Measured on a real
    # chunk file: 9 elements collapsing to one line, no error anywhere.
    set -l messages_text (cat $messages_file | string collect)

    # The merged message is multi-line prose, so a JSON string field would make it a
    # giant escaped blob — this is the callsite shape the <output> envelope exists
    # for. `llm-output --contract` rather than a hardcoded ~/dotfiles path, so a
    # worktree prompts with the contract its own extractor enforces.
    set -l contract (llm-output --contract | string collect)

    set -l prompt "Merge these commit message sections into one cohesive commit message.
- First line: 50 char max summary covering all changes
- Body: organized summary of all changes
- Keep it concise, no redundancy
- Output plain text only, no markdown

Sections:
$messages_text

$contract"

    if set -q _flag_verbose
        echo "    Merging "(grep -c '\-\-\-CHUNK\-\-\-' $messages_file)" chunk messages..." >&2
    end

    # See ai-chunk-files.fish for why the exit status alone can't be trusted here.
    set -l model claude-sonnet-5

    # The prompt here is only the chunk messages, so claude-p's 180s default is plenty.
    set -l rawfile (mktemp)
    claude-p --model $model "$prompt" >$rawfile
    set -l status_code $status
    set -l raw (cat $rawfile | string collect)

    # claude's own failure is reported BEFORE the envelope is touched. Running
    # llm-output unconditionally meant a timeout printed "no <output> envelope" on
    # stderr ahead of the real reason, which reads as the wrong diagnosis.
    if test $status_code -ne 0
        rm -f $rawfile
        if test $status_code -eq 124
            echo "ai-merge-commit-messages: claude timed out" >&2
        else
            echo "ai-merge-commit-messages: claude exited $status_code" >&2
            echo "  $raw" >&2
        end
        return 1
    end

    # Unwrap the envelope through a second file for the same reason as above: a
    # command substitution would report the status of `set`, and the exit code is
    # how llm-output distinguishes "no envelope" from "empty envelope".
    set -l bodyfile (mktemp)
    llm-output <$rawfile >$bodyfile
    set -l extract_code $status
    set -l result (cat $bodyfile | string collect)
    rm -f $rawfile $bodyfile
    # A leaked roleplay bookend used to arrive as a perfectly successful call, so this
    # function grew its own sniffs: an emptiness check and a
    # 'was retired on|may not exist' string match standing in for real error
    # detection. Both are gone. llm-output's nonzero exit covers a missing envelope,
    # an unclosed one and an empty body, and it never hands back raw text -- so
    # anything that is not the merged message now fails here rather than becoming
    # the commit message.
    if test $extract_code -ne 0
        echo "ai-merge-commit-messages: no usable <output> envelope in claude's reply" >&2
        echo "  "(string sub -l 200 "$raw") >&2
        return 1
    end

    printf '%s\n' $result
end
