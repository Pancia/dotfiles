function \?\? --description 'Shell oracle (keeps Claude open)'
    set -l system_prompt (cat ~/dotfiles/ai/templates/dotfiles_ai_shell_oracle.md | string collect)
    set -l user_prompt (string join " " $argv)
    claude --system-prompt "$system_prompt" "$user_prompt"
end
