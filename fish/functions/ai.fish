# AI helper function using claude
function ai --description 'Chat with AI using claude'
    set -l user_prompt (string join " " $argv)
    claude -p "$user_prompt"
end
