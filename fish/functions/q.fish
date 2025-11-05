# Command registry system
function q --description 'Execute registered command'
    source (ruby ~/dotfiles/lib/ruby/q.rb getreg "$argv[1]") $argv[2..-1]
end

function q! --description 'Register command'
    ruby ~/dotfiles/lib/ruby/q.rb setreg $argv
end

function qe --description 'Edit registered command'
    ruby ~/dotfiles/lib/ruby/q.rb editreg $argv
end

function q_ --description 'Delete registered command'
    ruby ~/dotfiles/lib/ruby/q.rb delreg $argv
end

function __q --description 'Direct q.rb access'
    ruby ~/dotfiles/lib/ruby/q.rb $argv
end
