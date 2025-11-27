function gitroot --description 'Get git repository root' --wraps 'git rev-parse'
    git rev-parse --show-toplevel $argv
end
