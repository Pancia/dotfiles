function my-claude-code-wrapper --description "Claude Code wrapper"
    # Unlock keychain for SSH/mosh sessions so Claude can access stored credentials
    if set -q SSH_CONNECTION
        echo "Unlocking keychain for remote session..."
        security unlock-keychain ~/Library/Keychains/login.keychain-db
        or begin
            echo "Failed to unlock keychain - Claude may not have subscription access"
        end
    end

    claude $argv
end
