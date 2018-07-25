use github.com/zzamboni/elvish-modules/alias

alias:new g git
alias:new ga git add
alias:new gaa git add --all
alias:new gsw git checkout
alias:new gd git diff --color-words
alias:new gds git diff --color-words --staged
alias:new gs git status
alias:new gc git commit --verbose
alias:new gca git commit --verbose --all
alias:new gr git reset
alias:new grh git reset HEAD
alias:new gpl git pull
alias:new gplr git pull --rebase
alias:new gp git push
alias:new gpb git push -u origin HEAD
alias:new gshow git show --color-words
alias:new gstash git stash
alias:new gsave git stash save
alias:bash-alias gl='GIT_PAGER="less -p \"(HEAD\""; git log --graph --all --decorate --abbrev-commit'

alias:new gundo git reset --soft HEAD~
alias:new gredo git commit --verbose -c ORIG_HEAD

alias:new gf git flow
alias:new gff git flow feature
alias:new gffs git flow feature start
alias:new gfff git flow feature finish
alias:new gffp git flow feature publish
alias:new gfr git flow release
alias:new gfrs git flow release start
alias:new gfrf git flow release finish
