function fish_title
    set -l ssh
    set -q SSH_TTY
    and set ssh "["(prompt_hostname | string sub -l 10 | string collect)"]"

    set -l title
    if set -q argv[1]
        set title $ssh (string sub -l 20 -- $argv[1]) (prompt_pwd -d 1 -D 1)
    else
        set -l command (status current-command)
        if test "$command" = fish
            set command
        end
        set title $ssh (string sub -l 20 -- $command) (prompt_pwd -d 1 -D 1)
    end

    # Prefix with VPC pane title if set (by iterm.py for VPC workspaces)
    if set -q VPC_PANE_TITLE[1]
        echo -- "$VPC_PANE_TITLE:" $title
    else
        echo -- $title
    end
end
