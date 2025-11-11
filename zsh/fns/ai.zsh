# brew install llm
# https://llm.datasette.io/en/stable/help.html
# https://llm.datasette.io/en/stable/templates.html#prompt-templates

function ai {
    claude -p "$*"
}

function ai_shell_oracle {
    claude -p --system-prompt "$(cat ~/dotfiles/ai/templates/dotfiles_ai_shell_oracle.yaml)" "$*"
}

alias '?'='ai_shell_oracle'

function ai_write_git_commit {
    claude -p --system-prompt "$(cat ~/dotfiles/ai/templates/dotfiles_ai_git_commit.yaml)" "$*"
}

function ai_git_commit {
    git commit --edit -m "$(git diff --staged | ai_write_git_commit)"
}

alias 'gcai'='ai_git_commit'
