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

function searchcmd {
    [ $(type -p searchcmd > /dev/null) ] && pip install searchcmd
    command searchcmd "$@"
}

function help {
    __DOC="help [cmd]"

    if [[ $# > 1 ]]; then
        searchcmd "$@"
    elif [[ "$1" =~ ^(help|-h|--help)$ ]]; then
        _helpHelp
    elif [[ -n "$1" ]]; then
        which "$1"
        __try tldr "$1"
    else
        _help -o | sed 's/^function //' | paste - - - | column -t
    fi
}
