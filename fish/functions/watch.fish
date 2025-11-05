# File watch and execute
function watch --description 'Watch file and re-execute on change'
    set -l cmd_file $argv[1]
    set -l args $argv[2..-1]
    set -l watch "."(basename $cmd_file)".watch"

    stat -f%m $cmd_file > $watch
    while true
        set -l mtime (stat -f%m $cmd_file)
        if test (cat $watch 2> /dev/null) != "$mtime"
            echo '======================'
            eval $cmd_file $args
            echo '======================'
            echo $mtime > $watch
        end
        sleep 1
    end
end
