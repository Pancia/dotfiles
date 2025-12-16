alias   "d?"="    ruby ~/dotfiles/lib/ruby/d.rb show"
function d  { cd `ruby ~/dotfiles/lib/ruby/d.rb getbookmark "$@"` }
function d! {     ruby ~/dotfiles/lib/ruby/d.rb setbookmark "$@" }
function de {     ruby ~/dotfiles/lib/ruby/d.rb editbookmark "$@" }
function d_ {     ruby ~/dotfiles/lib/ruby/d.rb delbookmark "$@" }
function __d {    ruby ~/dotfiles/lib/ruby/d.rb "$@" }

for p in $(ruby ~/dotfiles/lib/ruby/d.rb export); do
    export $p
done
