function ai_write_git_commit --description 'Generate git commit message'
    claude -p --system-prompt (cat ~/dotfiles/ai/templates/dotfiles_ai_git_commit.yaml) $argv
end
