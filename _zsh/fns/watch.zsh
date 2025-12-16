function watch {
    local cmd_file="$1"
    local args="${@:2}"
    local watch=".$(basename $cmd_file).watch"
    echo `stat -f%m $cmd_file` > $watch
    while true; do
        local mtime=`stat -f%m $cmd_file`
        if [ `cat $watch 2> /dev/null` != $mtime ]; then
            echo '======================'
            eval $cmd_file $args
            echo '======================'
            echo $mtime > $watch
        fi
        sleep 1
    done
}
