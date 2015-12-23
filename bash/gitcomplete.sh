source ~/.git-completion.bash

alias g='git'
__git_complete g _git
alias ga='git add'
__git_complete ga _git_add
alias gaa='git add --all'
alias gsw='git checkout'
__git_complete gsw _git_checkout
alias gm='git merge'
__git_complete gm _git_merge
alias gb='git branch'
__git_complete gb _git_branch
alias gd='git diff'
__git_complete gd _git_diff
alias gds='git diff --staged'
__git_complete gds _git_diff
alias gdc='git diff --staged'
__git_complete gdc _git_diff
alias gs='git status'
alias gc='git commit'
__git_complete gc _git_commit
alias gca='git commit --all'
__git_complete gca _git_commit
alias pull='git pull'
__git_complete pull _git_pull
alias push='git push && git push --tags'
__git_complete push _git_push
alias show='git show'
__git_complete show _git_show
alias stash='git stash'
__git_complete stash _git_stash
alias save='git stash save'
__git_complete save _git_stash
alias gl='git log --graph --all --decorate --abbrev-commit'
alias gt="git log --graph --abbrev-commit --decorate --date=relative --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(bold yellow)%d%C(reset)' --all"

alias gf='git flow'
alias gff='git flow feature'
alias gfr='git flow release'
export FEATURE_BRANCH="$(git rev-parse --abbrev-ref HEAD 2> /dev/null | sed -e 's/feature.//')"
