use epm

epm:install &silent-if-installed=$true \
    github.com/zzamboni/elvish-modules \
    github.com/zzamboni/elvish-completions \
    github.com/zzamboni/elvish-themes \
    github.com/xiaq/edit.elv \
    github.com/muesli/elvish-libs \
    github.com/iwoloschin/elvish-packages

use github.com/muesli/elvish-libs/git
use github.com/zzamboni/elvish-modules/util

# >>> TODO: broken with "Your elvish does not report a version number in elvish -buildinfo"
#use github.com/iwoloschin/elvish-packages/update
#update:check-commit &verbose
