function ai_write_git_commit --description 'Generate git commit message'
    set -l system_prompt (cat ~/dotfiles/ai/templates/dotfiles_ai_git_commit.md | string collect)
    claude -p --system-prompt "$system_prompt" $argv
end
