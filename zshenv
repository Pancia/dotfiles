export LEIN_SUPPRESS_USER_LEVEL_REPO_WARNINGS=1
export EDITOR='nvim'
export GIT_EDITOR='nvim'
export XDG_CONFIG_HOME=~/.config
export FEATURE_BRANCH="$(git rev-parse --abbrev-ref HEAD 2> /dev/null | sed -e 's/feature.//')"
export NVIM_LISTEN_ADDRESS=/tmp/mynvimsocket

setopt IGNORE_EOF

export US_NUM_DIFFS=4 #when looking at om next errors ex-data is 4th
export US_FRAME_LIMIT=20
export US_QUICK_FAIL=false
export US_FAIL_ONLY=true
export US_PRINT_LEVEL=4
export US_PRINT_LENGTH=4

[ -e ~/dotfiles/extra.env.zsh ] && source ~/dotfiles/extra.env.zsh
