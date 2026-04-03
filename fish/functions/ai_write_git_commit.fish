function ai_write_git_commit --description 'Generate git commit message from diff on stdin (outputs JSON)'
    set -l tmpfile (mktemp)
    cat >$tmpfile
    set -l system_prompt (cat ~/dotfiles/ai/templates/dotfiles_ai_git_commit.md | string collect)
    set -l raw (claude -p --output-format json --tools "" --system-prompt "$system_prompt" <$tmpfile | string collect)
    rm -f $tmpfile
    # Re-wrap claude's {result: ...} as {message: ...} for callers
    printf '%s' "$raw" | jq '{message: .result}'
end
