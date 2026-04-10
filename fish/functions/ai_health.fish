# AI health helper function using claude
function ai_health --description 'Health Chat with AI using claude'
    echo ""
    set_color yellow
    set -l line "~ ephemeral session ~ not persisted ~ not part of "(pwd)" ~"
    set -l bar (string repeat -n (string length -- $line) =)
    echo $bar
    echo $line
    echo $bar
    set_color normal
    echo ""

    my-claude-code-wrapper --process-label ai_health.fish --system-prompt (cat ~/private/ai/prompts/health.txt | string collect) \
        $argv
end
