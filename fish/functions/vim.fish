function vim --description 'Redirect vim to nvim' --wraps nvim
    set -lx TERM_TYPE nvim
    nvim $argv
end
