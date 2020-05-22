function a { fasd -a "$@" }
function d { fasd -d "$@" }
function f { fasd -f "$@" }
function s { fasd -si "$@" }
function sd { fasd -sid "$@" }
function sf { fasd -sif "$@" }
function z { fasd_cd -d "$@" }
function zz { fasd_cd -d -i "$@" }
function v { fasd -f -e nvim "$@" }

function dir { cd $(fasd -Rl "$@" | search) }
