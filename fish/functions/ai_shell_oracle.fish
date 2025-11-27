function ai_shell_oracle --description 'Ask shell oracle for help'
    claude -p --system-prompt (cat ~/dotfiles/ai/templates/dotfiles_ai_shell_oracle.yaml) $argv
end
