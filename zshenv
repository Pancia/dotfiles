export LEIN_SUPPRESS_USER_LEVEL_REPO_WARNINGS=1
export EDITOR='nvim'
export GIT_EDITOR='nvim'
export XDG_CONFIG_HOME=~/.config
export FEATURE_BRANCH="$(git rev-parse --abbrev-ref HEAD 2> /dev/null | sed -e 's/feature.//')"
export NVIM_LISTEN_ADDRESS=/tmp/nvimsocket
