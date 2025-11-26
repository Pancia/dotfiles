# Redirect vim to nvim
function vim --description 'Start nvim with socket' --wraps nvim
    if test -e .nvim.listen
        set -l socket (cat .nvim.listen)
        env TERM_TYPE=nvim nvim --listen $socket $argv
    else
        set -l socket "/tmp/"(basename (pwd))".socket"
        env TERM_TYPE=nvim nvim --listen $socket $argv
    end
end
