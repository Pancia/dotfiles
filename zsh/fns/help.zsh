function cheat {
    if [[ ! $(command -v cht.sh) ]]; then
        curl https://cht.sh/:cht.sh > /usr/local/bin/cht.sh
        chmod +x /usr/local/bin/cht.sh
    fi
    cht.sh "$@"
}

function _man_builtin {
    if [[ "$(whence -w $1 | cut -d' ' -f2)" =~ 'builtin|reserved' ]]; then
        man zshall | less -p "^[ ]+$1[- A-z]*\["
    fi
}

function man {
    case "$(whence -w $1 | cut -d' ' -f2)" in
        builtin|reserved) _man_builtin "$@";;
        *) command -p man "$@";;
    esac
}

alias '?'='help' # search local functions/aliases or use cheat.sh
