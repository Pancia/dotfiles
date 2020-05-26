alias "q?"="ruby ~/dotfiles/lib/ruby/q.rb list"
function q  { ruby ~/dotfiles/lib/ruby/q.rb doreg  "$@" }
function Q  { ruby ~/dotfiles/lib/ruby/q.rb setreg "$@" }
function q_ { ruby ~/dotfiles/lib/ruby/q.rb delreg "$@" }
