# Redirect vim to nvim
function vim --description 'Start nvim with socket' --wraps nvim
    if test -e .nvim.listen
        set -l socket (cat .nvim.listen)
        env TERM_TYPE=nvim nvim --listen $socket $argv
    else
        set -l socket "/tmp/"(basename (pwd) | string replace -ra '[^a-zA-Z0-9._-]' '_')".socket"
        env TERM_TYPE=nvim nvim --listen $socket $argv
    end
end
