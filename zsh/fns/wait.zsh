function wait-for {
    echo "[wait-for]: Waiting for \`test -e $1\`, will execute \`${@:2}\`"
    local i=0; while [ ! -e "$1" ]; do; sleep 1; ((i++)); echo -n "\rWaited: $i seconds"; done;
    echo -n "\nDone waiting for $1, executing: '${@:2}'."
    "${@:2}"
}
