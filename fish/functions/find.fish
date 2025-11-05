function find --description 'Remind to use fd instead' --wraps find
    if isatty stdout
        echo "[find] REMEMBER: use \`fd\`" >&2
    end
    command find $argv
end
