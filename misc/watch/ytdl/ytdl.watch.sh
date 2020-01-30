local return=0
mkdir -p ~/.log/ytdl

for f in `ls ~/Downloads/*.video.ytdl`; do
    echo "$(date '+%x %X') - $f" >> ~/.log/ytdl/log.txt

    tmp_err_log=$(mktemp)
    yt_id="$(basename $f .video.ytdl)"
    youtube-dl \
        -o '~/Downloads/ytdl/%(title)s__#__%(id)s.%(ext)s' \
        --no-progress \
        -f 140 "$yt_id" 2> $tmp_err_log \
        && mv "$f" ~/.Trash

    if [ -s "$tmp_err_log" ]; then
        cat "$tmp_err_log"
        cp "$tmp_err_log" ~/.log/ytdl/$yt_id.err
    fi

    return=42 # ie: spoon will print output
done

for f in `ls ~/Downloads/*.playlist.ytdl`; do
    echo "$(date '+%x %X') - $f" >> ~/.log/ytdl/log.txt

    tmp_err_log=$(mktemp)
    yt_id="$(basename $f .playlist.ytdl)"
    youtube-dl \
        -o '~/Downloads/ytdl/%(playlist_title)s/%(title)s__#__%(id)s.%(ext)s' \
        --no-progress \
        -f 140 "$yt_id" 2> $tmp_err_log \
        && mv "$f" ~/.Trash

    if [ -s "$tmp_err_log" ]; then
        cat "$tmp_err_log"
        cp "$tmp_err_log" ~/.log/ytdl/$yt_id.err
    fi

    return=42 # ie: spoon will print output
done

exit $return
