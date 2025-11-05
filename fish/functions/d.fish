# Directory bookmark system
function d --description 'Navigate to bookmarked directory'
    cd (ruby ~/dotfiles/lib/ruby/d.rb getbookmark $argv)
end

function d! --description 'Set directory bookmark'
    ruby ~/dotfiles/lib/ruby/d.rb setbookmark $argv
end

function de --description 'Edit directory bookmark'
    ruby ~/dotfiles/lib/ruby/d.rb editbookmark $argv
end

function d_ --description 'Delete directory bookmark'
    ruby ~/dotfiles/lib/ruby/d.rb delbookmark $argv
end

function __d --description 'Direct d.rb access'
    ruby ~/dotfiles/lib/ruby/d.rb $argv
end

# Export bookmarks
for p in (ruby ~/dotfiles/lib/ruby/d.rb export)
    set -l parts (string split '=' -- $p)
    set -gx $parts[1] $parts[2]
end
