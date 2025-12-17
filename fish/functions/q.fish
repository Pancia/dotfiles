# Command registry system
function q --description 'Execute registered command'
    source (ruby ~/dotfiles/lib/ruby/q.rb getreg "$argv[1]") $argv[2..-1]
end
