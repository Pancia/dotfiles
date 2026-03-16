# AI helper function using claude
function ai --description 'Chat with AI using claude'
    echo ""
    set_color yellow
    echo "======================================================================="
    echo "~ ephemeral session ~ not persisted ~ not part of the akashic records ~"
    echo "======================================================================="
    set_color normal
    echo ""

    my-claude-code-wrapper --process-label ai_assistant.fish --system-prompt (cat ~/dotfiles/ai/prompts/assistant.txt | string collect) \
        $argv
end
