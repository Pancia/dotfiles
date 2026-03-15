# AI health helper function using claude
function ai_health --description 'Health Chat with AI using claude'
    echo ""
    set_color yellow
    echo "======================================================================="
    echo "~ ephemeral session ~ not persisted ~ not part of the akashic records ~"
    echo "======================================================================="
    set_color normal
    echo ""

    set -l user_prompt (string join " " $argv)
    my-claude-code-wrapper --process-label ai_health.fish --system-prompt (cat ~/private/ai/prompts/health.txt | string collect) \
        -p "$user_prompt"
end
