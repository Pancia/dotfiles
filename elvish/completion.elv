use readline-binding

use github.com/xiaq/edit.elv/smart-matcher
smart-matcher:apply
edit:insert:binding[Tab] = { edit:completion:smart-start; edit:completion:trigger-filter }
# >>> TODO: broken "Space" is not correct
#edit:insert:binding[Space] = { edit:completion:accept }

use github.com/zzamboni/elvish-completions/vcsh
use github.com/zzamboni/elvish-completions/cd
use github.com/zzamboni/elvish-completions/ssh
use github.com/zzamboni/elvish-completions/builtins
