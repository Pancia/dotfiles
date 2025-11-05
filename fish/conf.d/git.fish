# Git configuration
set -gx GIT_EDITOR 'nvim'
set -gx FEATURE_BRANCH (git rev-parse --abbrev-ref HEAD 2> /dev/null | sed -e 's/feature.//')

