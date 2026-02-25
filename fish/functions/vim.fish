function vim --description 'Redirect vim to nvim' --wraps nvim
    env TERM_TYPE=nvim nvim $argv
end
