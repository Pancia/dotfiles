require 'shellwords'

$home_dir = %x[echo $HOME].strip

$file_fmt = "%(title)s__#__%(id)s.%(ext)s"
$playlist_fmt = "%(playlist_title)s"
$audio_code = "140"
$video_code = "18/22"

Dir["#{$home_dir}/Downloads/*.ytdl"].each { |f|
  ytid, videoType, downloadType, _ = File.basename(f).split(".")
  command = %{
    yt-dlp \
      -o '~/Downloads/ytdl/#{videoType == "playlist" ? $playlist_fmt : ""}/#{$file_fmt}' \
      --no-progress \
      -f #{downloadType == "audio" ? $audio_code : $video_code} \
      -- "#{Shellwords.escape ytid}" 2>&1 \
      && mv "#{f}" ~/.Trash/
  }
  system(command)
}
