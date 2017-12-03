function _help {
    ag '^function [^_][^ ]+' \
        --nofilename --nobreak \
        ~/dotfiles/zsh/functions.zsh \
        ~/dotfiles/zsh/functions/*.zsh \
        "$@" \
        | sort
}

function __try {
    local cmd=$1;
    local args="${@:2}";
    OUT="$($cmd $args)"; [[ $? == 0 ]] && echo $OUT
}

function _helpHelp { which help }

function help {
    __DOC="help [cmd]"

    if [[ $# > 1 ]]; then
        echo "[HELP]: CANNOT LOOKUP HELP ON MORE THAN ONE COMMAND"
        echo "$# - $@"
        exit 2
    elif [[ "$1" =~ ^(help|-h|--help)$ ]]; then
        _helpHelp
    elif [[ ! -z "$1" ]]; then
        which "$1"
        __try tldr "$1"
    else
        _help -o | sed 's/^function //' | paste - - - | column -t
    fi
}
