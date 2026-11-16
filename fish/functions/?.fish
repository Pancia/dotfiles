function \? --description 'Shell oracle (keeps Claude open)'
    set -l system_prompt (cat ~/dotfiles/ai/templates/dotfiles_ai_shell_oracle.md | string collect)
    set -l user_prompt (string join " " $argv)
    my-claude-code-wrapper --process-label shell-oracle --system-prompt "$system_prompt" "$user_prompt"
end
