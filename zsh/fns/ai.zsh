# brew install llm
# https://llm.datasette.io/en/stable/help.html
# https://llm.datasette.io/en/stable/templates.html#prompt-templates

function ai {
    llm -m gemini-2.5-flash "$*"
}

function ai_shell_oracle {
    llm -m gemini-2.5-flash --template dotfiles_ai_shell_oracle "$*"
}
alias '?'='ai_shell_oracle'
