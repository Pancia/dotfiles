# Vim session manager
set -l VIMS_EDIT_TEMPLATE '"VIMS SNIPPETS:
"terminal fish -c "..."
'

set -gx VIMS_SESSIONS_ROOT ~/dotfiles/nvim/sessions
set -gx VIM_BASE_SESSION ~/dotfiles/nvim/Session.vim

function __vimsType --description 'Get session type'
    echo (test -n "$argv[1]"; and echo $argv[1]; or echo "default")
end

function __vimsLoc --description 'Get session location'
    echo "$VIMS_SESSIONS_ROOT"(pwd)"/(__vimsType $argv[1]).vim"
end

function _vimsEdit --description 'Edit vim session'
    set -l session_location (__vimsLoc $argv[1])
    mkdir -p (dirname $session_location)
    if not test -f $session_location
        echo "$VIMS_EDIT_TEMPLATE" > "$session_location"
    end
    vim "$session_location"
end

function _vimsOpen --description 'Open vim session'
    if test (count $argv) -gt 1
        echo "[VIMS]: CAN ONLY OPEN ONE SESSION"
        return 2
    end
    set -l session_type (__vimsType $argv[1])
    if not test -f (__vimsLoc $session_type)
        echo "[VIMS]: FILE NOT FOUND '"(__vimsLoc $session_type)"'"
        return 2
    end
    vim --cmd "let g:vims_session_type='$session_type'" \
        --cmd "let g:vims_sessions_root='$VIMS_SESSIONS_ROOT'" \
        -S "$VIM_BASE_SESSION" $argv[2..-1]
end

function __vimsList --description 'List vim sessions'
    set -l MYDIR "$VIMS_SESSIONS_ROOT"(pwd)
    test -d "$MYDIR"; and ls "$MYDIR"
end

function _vimsShow --description 'Show vim sessions'
    for i in (__vimsList)
        echo "===> $i <==="
        cat $i
    end
end

function _vimsList --description 'List session names'
    __vimsList | xargs -I_ basename _ | sed 's/.vim$//'
end

function _vimsHelp --description 'Show vims help'
    echo "vims [edit|help|list|show] [SESSION]"
    echo "  vim session manager"
    echo
    tree $VIMS_SESSIONS_ROOT
end

function vims --description 'Vim session manager'
    set -l sub_cmd $argv[1]
    switch "$sub_cmd"
        case edit
            _vimsEdit $argv[2..-1]
        case help
            _vimsHelp $argv[2..-1]
        case list
            _vimsList $argv
        case show
            _vimsShow $argv
        case '*'
            _vimsOpen $argv
    end
end
