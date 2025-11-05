# Fish shell configuration
# Converted from ~/dotfiles/zsh/zshrc

function _not_same_inode
    test (stat -f '%i' $argv[1]) != (stat -f '%i' $argv[2])
end

function _ENSURE_RCS
    for rc in (find $HOME/dotfiles/rcs -type f -not -name '.*')
        set -l rc_dest (head -n 1 $rc | sed -E 's/.*<\[(.*)\]>.*/\1/')
        if not test -f "$HOME/$rc_dest"; or _not_same_inode "$HOME/$rc_dest" "$rc"
            mkdir -p (dirname "$HOME/$rc_dest")
            ln -f "$rc" "$HOME/$rc_dest"
        end
    end
end

function _ENSURE_SERVICES
    set -l dest $HOME/Library/LaunchAgents/
    for service_path in (find $HOME/dotfiles/services -type f -name '*.plist')
        set -l plist (basename $service_path)
        set -l service_name (basename $plist .plist)
        if not test -f "$dest/$plist"; or _not_same_inode "$dest/$plist" "$service_path"
            echo "[fish/config]: (re)loading $service_path"
            ln -f "$service_path" "$dest/"(basename $service_path)
            launchctl load ~/Library/LaunchAgents/$plist
            launchctl start (basename $plist .plist)
        end
    end
end

# Initialize RC and service management (in background)
_ENSURE_RCS &
_ENSURE_SERVICES &

# Disable fish greeting
set -g fish_greeting ""

# Source extra config if it exists
if test -e ~/dotfiles/fish/extra.fish
    source ~/dotfiles/fish/extra.fish
end

# Setup LLM templates symlink
set -l TEMPLATES_PATH (llm templates path)
if not test -L "$TEMPLATES_PATH"
    if test -e "$TEMPLATES_PATH"
        echo "Warning: $TEMPLATES_PATH exists but is not a symbolic link"
    else
        ln -s ~/dotfiles/ai/templates/ "$TEMPLATES_PATH"
    end
end

# Directory change tracking (converted from init.zsh)
set -gx LAST_DIR $HOME/.last_dir
echo "$PWD" > $LAST_DIR

function record_dir_change --on-variable PWD
    if test (cat $LAST_DIR) != "$PWD"
        # Fish doesn't have print -s, but we can append to history file directly
        echo "##dir## $PWD" >> $HOME/.local/share/fish/fish_history
        echo "$PWD" > $LAST_DIR
    end
end

# NVM setup (if using nvm.sh)
set -gx NVM_DIR "$HOME/.config/nvm"
if test -s "$NVM_DIR/nvm.sh"
    # Note: nvm.sh is a bash script, for fish consider using fisher install jorgebucaran/nvm.fish
    # For now, this won't work in fish - we'll need the fish-specific nvm plugin
    # bass source "$NVM_DIR/nvm.sh"  # Uncomment if you install bass plugin
end

# NOTE: conf.d/*.fish files are auto-loaded by fish
# NOTE: functions/*.fish files are auto-loaded **on demand** by fish

# d and q bookmark/registry aliases
alias 'd?' 'ruby ~/dotfiles/lib/ruby/d.rb show'
alias 'q?' 'ruby ~/dotfiles/lib/ruby/q.rb show'

# Cmds alias
alias '@' 'cmds'

# Git aliases
# Note: These are created as separate alias commands instead of functions
# Run this file to set up aliases, or define them individually

alias ga 'git add'
alias gaa 'git add --all'
alias gc 'git commit --verbose'
alias gca 'git commit --verbose --all'
# ./ai.zsh defines gcai -> edit git commit message initialized by ai
alias gd 'git diff --color-words'
alias gds 'gd --staged'
alias gl 'git log --graph --all --decorate --abbrev-commit'
alias gs 'git status'
alias gsave 'git stash save'
alias gshow 'git show --color-words'
alias gstash 'git stash'
alias gsw 'git checkout'

# Error messages for dangerous operations
alias gp 'echo "ERROR: USE: vim git fuGITive (whichkey plugin)"; false'
alias gpf 'echo "ERROR: USE: vim git fuGITive (whichkey plugin)"; false'
alias gpl 'echo "ERROR: USE: vim git fuGITive (whichkey plugin)"; false'
