function my-claude-code-wrapper --description "Claude Code wrapper"
    argparse --ignore-unknown 'process-label=' -- $argv

    # Unlock keychain for SSH/mosh sessions so Claude can access stored credentials
    if set -q SSH_CONNECTION
        echo "Unlocking keychain for remote session..."
        security unlock-keychain ~/Library/Keychains/login.keychain-db
        or begin
            echo "Failed to unlock keychain - Claude may not have subscription access"
        end
    end

    set -l timestamp (date +%H:%M:%S)
    set -l label (basename (pwd))
    if set -q _flag_process_label
        set label "$label @ $_flag_process_label $timestamp"
    else
        set label "$label $timestamp"
    end
    proc-label "claude [$label]" claude $argv
end
