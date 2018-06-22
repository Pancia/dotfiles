local smartcd_public_root=~/dotfiles/smartcd
local smartcd_private_root=~/.smartcd
local smartcd_global_public_root=$smartcd_public_root/.__smartcdGlobal
local smartcd_global_private_root=$smartcd_private_root/.__smartcdGlobal

local SMARTCD_EDIT_TEMPLATE="#########################################
######## HELLO FROM SMARTCD EDIT ########
#########################################
"

function __smartcdRoot {
    case $1 in
        public) echo $smartcd_public_root ;;
        private) echo $smartcd_private_root ;;
        *) echo $smartcd_public_root ;;
    esac
}

function __smartcdType { echo "$1" }

function __smartcdLoc {
    if [[ "$1" == "global" ]]; then
        case $3 in
            public) echo $smartcd_global_public_root.$2.zsh ;;
            private) echo $smartcd_global_private_root.$2.zsh ;;
            *) echo $smartcd_global_public_root.$2.zsh ;;
        esac
    else
        echo "$(__smartcdRoot $2)${3:-`pwd`}/$(__smartcdType $1).zsh"
    fi
}

function _smartcdEdit {
    [[ "$1" =~ "enter|leave|global" ]] ||
        (>&2 echo "first arg should be enter leave or global" && exit 1)
    [[ "$1" =~ "global" ]] && [[ "$2" =~ "enter|leave" ]] ||
        (>&2 echo "when global, second arg should be enter or leave" && exit 1)
    local script_loc="$(__smartcdLoc $@)"
    mkdir -p "$(dirname $script_loc)"
    [[ ! -f $script_loc ]] && echo "$SMARTCD_EDIT_TEMPLATE" > "$script_loc"
    $EDITOR "$script_loc"
    chmod u+x "$script_loc"
    [[ -z "$(cat $script_loc | sed '/^#/d')" ]] && command rm "$script_loc"
}

function __smartcdList {
    [ -e "${smartcd_private_root}$(pwd)" ] && find "${smartcd_private_root}$(pwd)" -type f -maxdepth 1
    [ -e "${smartcd_public_root}$(pwd)" ] && find "${smartcd_public_root}$(pwd)" -type f -maxdepth 1
}

function _smartcdShow { for i in `__smartcdList`; do echo "===> $i <==="; cat $i | sed '/^\#/d'; done }

function _smartcdList { __smartcdList | xargs -I_ basename _ | sed 's/.zsh$//' }

function _smartcdHelp { echo $__DOC }

function _smartcd {
    local __DOC="
    smartcd [edit|list|show|help]
        - smartcd edit (enter|leave) [public|private]
        - smartcd list
        - smartcd show [TYPE]
        - smartcd help
    "
    local sub_cmd="$1"
    case "$sub_cmd" in
        edit) _smartcdEdit "${@:2}" ;;
        list) _smartcdList "$@" ;;
        show) _smartcdShow "$@" ;;
        help) _smartcdHelp "$@" ;;
        *) _smartcdHelp "$@" ;;
    esac
}

function __smartcdNextDir {
    case "$1" in
        enter) echo "$2/$3" ;;
        leave) echo "$(dirname $2)" ;;
    esac
}

function __smartcdExecute {
    local dir="$(__smartcdNextDir $@)"
    local pub_script="$(__smartcdLoc $1 public $dir)"
    ([ -e $pub_script ] && cd $dir && $SHELL $pub_script)
    local prv_script="$(__smartcdLoc $1 private $dir)"
    ([ -e $prv_script ] && cd $dir && $SHELL $prv_script)
}

function __smartcdGlobalExec {
    local dir="$(__smartcdNextDir $@)"
    local pub_global="$(__smartcdLoc global $1 public)"
    ([ -e $pub_global ] && cd $dir && $SHELL $pub_global $dir)
    local prv_global="$(__smartcdLoc global $1 private)"
    ([ -e $prv_global ] && cd $dir && $SHELL $prv_global $dir)
}

function _smartcd_cd {
    local enter_wd="$1"
    local leave_wd="$2"
    IFS='/' read -rA enter <<< "$(echo $enter_wd | sed 's/^\///')"
    IFS='/' read -rA leave <<< "$(echo $leave_wd | sed 's/^\///')"
    local max_N="$(( ${#leave} > ${#enter} ? ${#leave} : ${#enter} ))"

    for i in $(seq 1 $max_N); do
        if [[ "${leave[i]}" == "${enter[i]}" ]]; then
            leave[$i]=""
            enter[$i]=""
        fi
    done

    local cwd="${leave_wd:-/}"
    for i in $(seq $max_N -1 1); do
        if [ -n "${leave[i]}" ]; then
            __smartcdGlobalExec leave $cwd ${leave[i]}
            __smartcdExecute leave $cwd ${leave[i]}
            cwd="$(__smartcdNextDir leave $cwd ${leave[i]})"
        fi
    done

    for i in $(seq 1 $max_N); do
        if [ -n "${enter[i]}" ]; then
            __smartcdGlobalExec enter $cwd ${enter[i]}
            __smartcdExecute enter $cwd ${enter[i]}
            cwd="$(__smartcdNextDir enter $cwd ${enter[i]})"
        fi
    done
}

function cd {
    leave_wd="$(pwd)"
    builtin cd "$@"
    enter_wd="$(pwd)"

    _smartcd_cd "$enter_wd" "$leave_wd"
}

if [ ! $BIN ]; then
    _smartcd_cd "$(pwd)"
fi
