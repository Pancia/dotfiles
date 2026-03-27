function ai_write_git_commit --description 'Generate git commit message from diff on stdin'
    set -l tmpfile (mktemp)
    cat >$tmpfile
    set -l system_prompt (cat ~/dotfiles/ai/templates/dotfiles_ai_git_commit.md | string collect)
    set -l json_output (claude -p --output-format json --system-prompt "$system_prompt" <$tmpfile | string collect)
    rm -f $tmpfile
    printf '%s' "$json_output" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['result'])"
end
