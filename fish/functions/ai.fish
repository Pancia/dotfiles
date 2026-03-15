# AI helper function using claude
function ai --description 'Chat with AI using claude'
    set -l user_prompt (string join " " $argv)
    my-claude-code-wrapper --process-label ai_assistant.fish --system-prompt (cat ~/dotfiles/ai/prompts/assistant.txt | string collect) \
        -p "$user_prompt"
end
