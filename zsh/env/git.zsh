export GIT_EDITOR='nvim'
export FEATURE_BRANCH="$(git rev-parse --abbrev-ref HEAD 2> /dev/null | sed -e 's/feature.//')"
