function ai_shell_oracle --description 'Ask shell oracle for help'
    set -l system_prompt (cat ~/dotfiles/ai/templates/dotfiles_ai_shell_oracle.md | string collect)
    claude -p --system-prompt "$system_prompt" $argv
end
