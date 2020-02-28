for f in `ls ~/Downloads/*.video.ytdl`; do
    yt_id="$(basename $f .video.ytdl)"
    youtube-dl \
        -o '~/Downloads/ytdl/%(title)s__#__%(id)s.%(ext)s' \
        --no-progress \
        -f 140 "$yt_id" 2>&1 \
        && mv "$f" ~/.Trash
done

for f in `ls ~/Downloads/*.playlist.ytdl`; do
    yt_id="$(basename $f .playlist.ytdl)"
    youtube-dl \
        -o '~/Downloads/ytdl/%(playlist_title)s/%(title)s__#__%(id)s.%(ext)s' \
        --no-progress \
        -f 140 "$yt_id" 2>&1 \
        && mv "$f" ~/.Trash
done
