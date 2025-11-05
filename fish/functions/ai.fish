# AI helper functions using llm
function ai --description 'Chat with AI using gemini-2.5-flash'
    llm -m gemini-2.5-flash $argv
end

function ai_shell_oracle --description 'Ask shell oracle for help'
    llm -m gemini-2.5-flash --template dotfiles_ai_shell_oracle $argv
end

function \? --description 'Alias for ai_shell_oracle' --wraps ai_shell_oracle
    ai_shell_oracle $argv
end

function ai_write_git_commit --description 'Generate git commit message'
    git diff --staged | llm -m gemini-2.5-flash --template dotfiles_ai_git_commit $argv
end

function ai_git_commit --description 'Commit with AI-generated message'
    git commit --edit -m (ai_write_git_commit)
end

alias gcai 'ai_git_commit'
