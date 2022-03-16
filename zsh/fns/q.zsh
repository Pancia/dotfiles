alias   "q?"=" ruby ~/dotfiles/lib/ruby/q.rb show"
function q  { source `ruby ~/dotfiles/lib/ruby/q.rb getreg "$@"` }
function q! {   ruby ~/dotfiles/lib/ruby/q.rb setreg "$@" }
function qe {   ruby ~/dotfiles/lib/ruby/q.rb editreg "$@" }
function q_ {   ruby ~/dotfiles/lib/ruby/q.rb delreg "$@" }
function __q {  ruby ~/dotfiles/lib/ruby/q.rb "$@" }
