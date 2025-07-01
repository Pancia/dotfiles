require 'json'
require 'shellwords'

system("echo;date")

$home_dir = %x[echo $HOME].strip

$playlist_fmt = "%(playlist_title)s"
$audio_code = "bestaudio[ext=m4a]"
$video_code = "bestvideo[ext=mp4][height<=480][protocol=https]+bestaudio"

Dir["#{$home_dir}/Downloads/*.ytdl"].each { |f|
  ytid, videoType, downloadType, _ = File.basename(f).split(".")
  if downloadType == "audio" or downloadType == "video"
    command = %{
        yt-dlp \
          -o '~/Downloads/ytdl/#{downloadType}/#{videoType == "playlist" ? $playlist_fmt : ""}/%(channel)s__$__%(title)s__#__%(id)s.%(ext)s' \
          --no-progress \
          -f "#{downloadType == "video" ? $video_code : $audio_code}" \
          -- "#{Shellwords.escape ytid}" 2>&1 \
          && mv "#{Shellwords.escape f}" ~/.Trash/
    }
  else
    command = %{
      yt-dlp \
        -o '~/Downloads/ytdl/#{downloadType}/%(channel)s__$__%(title)s__#__%(id)s.%(ext)s' \
        --skip-download --write-subs --write-auto-subs \
        --sub-langs en --convert-subs srt \
        --no-progress \
        -- "#{Shellwords.escape ytid}" 2>&1 \
        && mv "#{Shellwords.escape f}" ~/.Trash
    }
  end
  system(command)
}
