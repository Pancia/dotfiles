alias   "q?"=" ruby ~/dotfiles/lib/ruby/q.rb show"
function q  { `ruby ~/dotfiles/lib/ruby/q.rb getreg "$@"` }
function q! {  ruby ~/dotfiles/lib/ruby/q.rb setreg "$@" }
function q_ {  ruby ~/dotfiles/lib/ruby/q.rb delreg "$@" }
