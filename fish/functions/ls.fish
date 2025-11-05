function ls --description 'ls with human-readable sizes' --wraps ls
    command ls -h $argv
end
