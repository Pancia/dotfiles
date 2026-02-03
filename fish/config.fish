# Fish shell configuration
# Converted from ~/dotfiles/zsh/zshrc

function _not_same_inode
    test (stat -f '%i' $argv[1]) != (stat -f '%i' $argv[2])
end

function _ENSURE_RCS
    set -l manifest "$HOME/dotfiles/rcs/MANIFEST"
    if not test -f "$manifest"
        if status is-interactive; and isatty stderr
            echo "[_ENSURE_RCS] warning: $manifest not found" >&2
        end
        return 1
    end

    # Collect all source files listed in manifest
    set -l manifest_files

    while read -l line
        # Skip comments and empty lines
        string match -rq '^\s*#' -- $line; and continue
        string match -rq '^\s*$' -- $line; and continue

        # Parse "source -> destination" format
        set -l parts (string split ' -> ' -- $line)
        if test (count $parts) -ne 2
            continue
        end

        set -l rc_name (string trim -- $parts[1])
        set -l rc_dest (string trim -- $parts[2])
        # Expand $HOME in destination path
        set -l rc_dest (string replace '$HOME' "$HOME" -- $rc_dest)

        # Support absolute paths (starting with / or $HOME) for rc_name
        set -l rc_path
        if string match -rq '^(/|\$HOME)' -- $rc_name
            set rc_path (string replace '$HOME' "$HOME" -- $rc_name)
        else
            set rc_path "$HOME/dotfiles/rcs/$rc_name"
        end

        set -a manifest_files (basename $rc_name)

        # Handle directories (use symlinks since hard links don't work for dirs)
        if test -d "$rc_path"
            if not test -L "$rc_dest"; or test (readlink "$rc_dest") != "$rc_path"
                mkdir -p (dirname "$rc_dest")
                ln -sfn "$rc_path" "$rc_dest"
            end
            continue
        end

        if not test -f "$rc_path"
            if status is-interactive; and isatty stderr
                echo "[_ENSURE_RCS] warning: $rc_path not found" >&2
            end
            continue
        end

        if not test -f "$rc_dest"; or _not_same_inode "$rc_dest" "$rc_path"
            mkdir -p (dirname "$rc_dest")
            ln -f "$rc_path" "$rc_dest"
        end
    end < "$manifest"

    # Check for files in rcs/ not listed in manifest
    if status is-interactive; and isatty stderr
        for rc_file in $HOME/dotfiles/rcs/*
            # Skip directories
            test -d "$rc_file"; and continue

            set -l filename (basename $rc_file)
            # Skip MANIFEST itself and common non-rc items
            test "$filename" = "MANIFEST"; and continue
            string match -q '__pycache__' -- $filename; and continue
            string match -q '*.pyc' -- $filename; and continue

            if not contains -- $filename $manifest_files
                echo "[_ENSURE_RCS] warning: rcs/$filename not in MANIFEST" >&2
            end
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

function _ENSURE_CONF_D
    set -l dest $HOME/.config/fish/conf.d/
    mkdir -p $dest
    for conf_file in $HOME/dotfiles/fish/conf.d/*.fish
        set -l filename (basename $conf_file)
        if not test -f "$dest/$filename"; or _not_same_inode "$dest/$filename" "$conf_file"
            ln -f "$conf_file" "$dest/$filename"
        end
    end
end

function _ENSURE_COMPLETIONS
    set -l dest $HOME/.config/fish/completions/
    mkdir -p $dest
    for comp_file in $HOME/dotfiles/fish/completions/*.fish
        set -l filename (basename $comp_file)
        if not test -f "$dest/$filename"; or _not_same_inode "$dest/$filename" "$comp_file"
            ln -f "$comp_file" "$dest/$filename"
        end
    end
end

# Initialize RC and service management (in background)
_ENSURE_RCS &
_ENSURE_SERVICES &
_ENSURE_CONF_D &
_ENSURE_COMPLETIONS &

function _ENSURE_FISH_PLUGINS
    set -l source_file $HOME/dotfiles/fish/fish_plugins
    set -l dest_file $HOME/.config/fish/fish_plugins
    if test -f "$source_file"
        if not test -f "$dest_file"; or _not_same_inode "$dest_file" "$source_file"
            ln -f "$source_file" "$dest_file"
        end
    end
end

# Initialize fish plugins file
_ENSURE_FISH_PLUGINS

# Fisher plugin manager - auto-bootstrap
if not functions -q fisher
    set -q XDG_CONFIG_HOME; or set XDG_CONFIG_HOME ~/.config
    curl https://git.io/fisher --create-dirs -sLo $XDG_CONFIG_HOME/fish/functions/fisher.fish
    source $XDG_CONFIG_HOME/fish/functions/fisher.fish
end

# Source chpwd hooks (event handlers need explicit sourcing)
source ~/dotfiles/fish/functions/chpwd.fish

# Disable fish greeting
set -g fish_greeting ""

# Set SHELL environment variable
set -gx SHELL (command --search fish)

# Source extra config if it exists
if test -e ~/dotfiles/fish/extra.fish
    source ~/dotfiles/fish/extra.fish
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

# Git aliases - disabled, use `g` command instead
function __git_use_g; echo "Use 'g' command instead (git which-key menu)"; false; end
alias ga  __git_use_g
alias gaa __git_use_g
alias gc  __git_use_g
alias gca __git_use_g
alias gcai __git_use_g
alias gd  __git_use_g
alias gds __git_use_g
alias gl  'git log --graph --all --decorate --abbrev-commit'
alias gs  'git status'
alias gsave __git_use_g
alias gshow __git_use_g
alias gstash __git_use_g
alias gsw __git_use_g
alias grs __git_use_g
alias gp  __git_use_g
alias gpf __git_use_g
alias gpl __git_use_g

# Abbreviations
abbr -a cc my-claude-code-wrapper
abbr -a oo my-opencode-wrapper

# Key bindings
if status is-interactive
    # Bind Ctrl-L to clear screen while keeping tide prompt visible
    bind \cl clear_keep_prompt

    # Only show reminders in a real terminal (not hs.execute, etc.)
    if isatty stdout
        echo "Remember to try out:"
        echo "scooter (find&replace), yazi(tui file manager), lazygit"
        echo "d / p / v -- <TAB> or standalone"
    end
end
