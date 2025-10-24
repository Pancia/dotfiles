require 'json'
require 'shellwords'

system("echo;date")
system("which yt-dlp")
system("yt-dlp --version")

$home_dir = %x[echo $HOME].strip

$playlist_fmt = "%(playlist_title)s"
$audio_code = "bestaudio"
$video_code = "bestvideo[ext=mp4][height<=480][vcodec^=avc]+bestaudio"
$progress_flag = ARGV.include?('--show-progress') ? '' : '--no-progress'

Dir["#{$home_dir}/Downloads/*.ytdl"].each { |f|
  ytid, videoType, downloadType, _ = File.basename(f).split(".")
  if downloadType == "audio" or downloadType == "video" or downloadType == "music"
    command = %{
        yt-dlp \
          -o '~/Downloads/ytdl/#{downloadType}/#{videoType == "playlist" ? $playlist_fmt : ""}/%(channel)s__$__%(title)s__#__%(id)s.%(ext)s' \
          #{$progress_flag} \
          -f "#{downloadType == "video" ? $video_code : $audio_code}" \
          -- "#{Shellwords.escape ytid}" 2>&1 \
          && mv "#{Shellwords.escape f}" ~/.Trash/
    }
    system(command)
    out_dir = File.expand_path("~/Downloads/ytdl/#{downloadType}")
    # Find all .mp4 files that don't have corresponding .m4a files
    Dir.glob("#{out_dir}/*.mp4").each do |mp4_file|
      m4a_file = mp4_file.sub(/\.mp4$/, '.m4a')
      unless File.exist?(m4a_file)
        system("ffmpeg -i #{Shellwords.escape mp4_file} #{Shellwords.escape m4a_file} \
               && mv #{Shellwords.escape mp4_file} ~/.Trash/")
      end
    end
  else
    out_file = "~/Downloads/ytdl/#{downloadType}/%(channel)s__$__%(title)s__#__%(id)s.%(ext)s"
    command = %{
      yt-dlp \
        -o '#{out_file}' \
        --skip-download --write-subs --write-auto-subs \
        --sub-langs en --convert-subs srt \
        #{$progress_flag} \
        -- "#{Shellwords.escape ytid}" 2>&1
    }
    system(command)
    out_dir = File.expand_path("~/Downloads/ytdl/#{downloadType}")

    # Check if any .srt files were created for this video
    srt_files = Dir.glob("#{out_dir}/*__#__#{ytid}.*.srt")

    if srt_files.empty?
      # No subtitles available, download audio and transcribe
      audio_file = "#{out_dir}/%(channel)s__$__%(title)s__#__%(id)s.%(ext)s"
      download_command = %{
        yt-dlp \
          -o '#{audio_file}' \
          #{$progress_flag} \
          -f "#{$audio_code}" \
          -- "#{Shellwords.escape ytid}" 2>&1
      }
      system(download_command)

      # Find the downloaded audio file and transcribe it
      audio_files = Dir.glob("#{out_dir}/*__#__#{ytid}.*")
      audio_files.each do |audio_file_path|
        next if audio_file_path.end_with?('.txt', '.srt')
        txt_file = audio_file_path.sub(/\.[^.]+$/, '.txt')
        system("transcribe #{Shellwords.escape audio_file_path} | tee #{Shellwords.escape txt_file}")
      end
    else
      # Convert .srt files to .txt
      srt_files.each do |srt_file|
        txt_file = srt_file.sub(/\.srt$/, '.txt')
        unless File.exist?(txt_file)
          system("srttotxt", srt_file)
        end
      end
    end

    # Move the trigger file to trash after all processing
    system("mv #{Shellwords.escape f} ~/.Trash/")
  end
}
