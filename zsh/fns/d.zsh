alias   "d?"="    ruby ~/dotfiles/lib/ruby/d.rb show"
function d  { cd `ruby ~/dotfiles/lib/ruby/d.rb getbookmark "$@"` }
function d! {     ruby ~/dotfiles/lib/ruby/d.rb setbookmark "$@" }
function d_ {     ruby ~/dotfiles/lib/ruby/d.rb delbookmark "$@" }
function __d {    ruby ~/dotfiles/lib/ruby/d.rb "$@" }
