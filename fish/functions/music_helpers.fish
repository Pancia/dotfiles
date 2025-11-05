# Music management functions
function __yt_lookup --description 'Lookup YouTube search for music'
    set -l search (music show -f '.id' --yt-search $argv[1])
    echo $search
    open -a Firefox "https://www.youtube.com/results?search_query=$search"
end

function __ytdl_dl --description 'Download YouTube music'
    mv $MUSIC_DIR/$argv[1].m4a $MUSIC_DIR/$argv[1].old.m4a
    yt-dlp -f 140 $ytid -o $MUSIC_DIR/$argv[1].m4a $argv[2]
    music mtag $argv[1]
end

function __ytdl_id --description 'Download music with YouTube ID'
    __yt_lookup $argv[1]
    echo "youtube id:"
    read ytid
    if test -n "$ytid"
        __ytdl_dl $argv[1]
    end
end

function __ytdl_id_async --description 'Download music asynchronously'
    __yt_lookup $argv[1]
    echo "youtube id:"
    read ytid
    if test -n "$ytid"
        __ytdl_dl $argv[1] --no-progress &
    end
end

function __edit_id --description 'Interactive music ID editor'
    echo "$curr /" (wc -l < $marked)
    echo "ID: " $argv[1]
    music show -f '.id' --yt-search $argv[1]
    echo '(c)mus, (a)udacity, (y)tdl, (e)dit, (d)one'
    read cmd
    switch $cmd
        case a
            open -a audacity $MUSIC_DIR/$argv[1].m4a
            __edit_id $argv[1]
        case c
            cmus-remote -f $MUSIC_DIR/$argv[1].m4a
            __edit_id $argv[1]
        case e
            music edit -f .id $argv[1]
            __edit_id $argv[1]
        case y
            __ytdl_id $argv[1]
            __edit_id $argv[1]
        case d
            echo "DONE with $argv[1]"
        case '*'
            __edit_id $argv[1]
    end
end

function __fix_marked_music --description 'Fix marked music interactively'
    set -l marked (mktemp)
    music search --raw -f 'select(.marked) | .id' | sort > $marked
    set -l curr 1
    for i in (cat $marked)
        music show $i
        __edit_id $i
        echo
        echo
        set curr (math $curr + 1)
    end
end
