# Fish shell configuration
# Converted from ~/dotfiles/zsh/zshrc

function _not_same_inode
    test (stat -f '%i' $argv[1]) != (stat -f '%i' $argv[2])
end

# rcs/MANIFEST pairs: hardlinked files, symlinked directories. The logic lives in
# bin/rcs-sync, which resolves a split pair by which side changed since the last
# sync instead of letting the repo copy always win -- that silently reverted
# apps (Claude Code's /effort, /permissions) that save by atomic rename.
function _ENSURE_RCS
    $HOME/dotfiles/bin/rcs-sync $argv
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
# fish cannot background a *function* -- `func &` runs in the foreground -- so
# rcs-sync is launched as a real process. Interactive shells only: `fish -c` and
# fish scripts paid ~280ms each for it, and Claude sessions sync via hooks.
if status is-interactive
    command $HOME/dotfiles/bin/rcs-sync --check-unlisted &
    disown 2>/dev/null
end
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

# Per-pane journal for `revive` (event handlers, same reason)
source ~/dotfiles/fish/functions/revive-journal.fish

# Disable fish greeting
set -g fish_greeting ""

# Set SHELL environment variable
set -gx SHELL (command --search fish)

# Source extra config if it exists
if test -e ~/dotfiles/fish/extra.fish
    source ~/dotfiles/fish/extra.fish
end

# Directory change tracking (converted from init.zsh)
set -gx LAST_DIR $HOME/.local/state/fish/last_dir
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

# Git/jj aliases - most redirect to `g` menu, a few work directly
function __git_use_g; echo "Use 'g' command instead (git/jj which-key menu)"; false; end
alias ga  __git_use_g
alias gaa __git_use_g
alias gc  __git_use_g
alias gca __git_use_g
alias gcai __git_use_g
# gd -> fish/functions/gd.fish
function gds; if test -d .jj; jj diff; else; git diff --staged --color-words; end; end
function gl; if test -d .jj; jj log --stat; else; git log --graph --all --decorate --abbrev-commit --stat; end; end
function gs; set -l sep (set_color brblack)(string repeat -n 60 -)(set_color normal); if test -d .jj; jj diff --stat; and echo $sep; and jj status; else; git diff --stat; and echo $sep; and git status; end; end
alias gsave __git_use_g
function gshow; if test -d .jj; jj show $argv; else; git show --patch-with-raw $argv; end; end
alias gstash __git_use_g
alias gsw __git_use_g
alias grs __git_use_g
alias gp  __git_use_g
alias gpf __git_use_g
alias gpl __git_use_g

# Key bindings
if status is-interactive
    # Bind Ctrl-L to clear screen while keeping tide prompt visible
    bind \cl clear_keep_prompt

    # Only show reminders in a real terminal (not hs.execute, etc.)
    if isatty stdout
        # 1440 minutes: at most once a day, across every pane
        cache global try-out-reminder 1440 showTryOutReminder

        # What this pane was doing before it died. Pre-rendered at adoption, so
        # this is a file test and a read -- no fork, no python.
        revive-banner
    end
end
