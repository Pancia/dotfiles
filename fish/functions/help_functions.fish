# Help and documentation functions
function cheat --description 'Use cht.sh for quick reference'
    if not command -v cht.sh &> /dev/null
        curl https://cht.sh/:cht.sh > /usr/local/bin/cht.sh
        chmod +x /usr/local/bin/cht.sh
    end
    cht.sh $argv
end

function _man_builtin --description 'Man page for shell builtin'
    set -l cmd_type (type -t $argv[1] 2>/dev/null)
    if string match -q -r 'builtin|function' "$cmd_type"
        man fish | less -p "^[ ]+$argv[1][- A-z]*\["
    end
end

function man --description 'Enhanced man command' --wraps man
    set -l cmd_type (type -t $argv[1] 2>/dev/null)
    switch "$cmd_type"
        case 'builtin' 'function'
            _man_builtin $argv
        case '*'
            command man $argv
    end
end
