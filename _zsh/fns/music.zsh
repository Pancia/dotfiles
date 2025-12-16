function __yt_lookup() {
    search="$(music show -f '.id' --yt-search $1)"
    echo $search
    open -a Firefox "https://www.youtube.com/results?search_query=$search"
}

function __ytdl_dl() {
    mv $MUSIC_DIR/$1.m4a $MUSIC_DIR/$1.old.m4a
    yt-dlp -f 140 $ytid -o $MUSIC_DIR/$1.m4a $2
    music mtag $1
}

# NOTE used by [[~/dotfiles/lib/lua/seeds/cmus.lua]]
function __ytdl_id() {
    __yt_lookup $1
    echo "youtube id:"
    read ytid
    if test -z $ytid; then else
        __ytdl_dl $1
    fi
}

function __ytdl_id_async() {
    __yt_lookup $1
    echo "youtube id:"
    read ytid
    if test -z $ytid; then else
        (__ytdl_dl $1 --no-progress) &
    fi
}

function __edit_id() {
    echo "$curr /" `wc -l < $marked`
    echo "ID: " $1
    music show -f '.id' --yt-search $1
    echo '(c)mus, (a)udacity, (y)tdl, (e)dit, (d)one'
    read cmd;
    case $cmd in
        a) open -a audacity $MUSIC_DIR/$1.m4a; __edit_id $1 ;;
        c) cmus-remote -f $MUSIC_DIR/$1.m4a ; __edit_id $1 ;;
        e) music edit -f .id $1; __edit_id $1 ;;
        y) __ytdl_id $1; __edit_id $1 ;;
        d) echo "DONE with $1" ;;
        *) __edit_id $1 ;;
    esac
}

function __fix_marked_music() {
    marked=$(mktemp)
    music search --raw -f 'select(.marked) | .id' | sort > $marked
    curr=1
    for i in `cat $marked`; do
        music show $i;
        __edit_id $i
        echo
        echo
        curr=$((1+$curr))
    done
}
