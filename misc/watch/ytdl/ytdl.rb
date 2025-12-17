require 'json'
require 'shellwords'

system("echo;date")
system("which yt-dlp")
system("yt-dlp --version")

# Configuration
YTDL_OUTPUT_DIR = File.expand_path("~/Cloud/ytdl")
YTDL_DOWNLOADS_DIR = File.expand_path("~/Downloads")

$playlist_fmt = "%(playlist_title)s"
$audio_code = "bestaudio"
$video_code = "bestvideo[ext=mp4][height<=480][vcodec^=avc]+bestaudio"
$progress_flag = ARGV.include?('--show-progress') ? '' : '--no-progress'

def run_ytdlp(base_args, ytid)
  command = "yt-dlp #{base_args} -- \"#{Shellwords.escape ytid}\" 2>&1"
  puts(command)
  output = %x{#{command}}
  puts output
  success = $?.success?

  # Retry with cookies if age-restricted
  if !success && output =~ /Sign in to confirm your age|age-restricted|login required/i
    puts "\n[Age-restricted detected, retrying with cookies...]"
    command = "yt-dlp #{base_args} --cookies-from-browser brave -- \"#{Shellwords.escape ytid}\" 2>&1"
    puts(command)
    output = %x{#{command}}
    puts output
    success = $?.success?
  end

  success
end

Dir["#{YTDL_DOWNLOADS_DIR}/*.ytdl"].each { |f|
  ytid, videoType, downloadType, _ = File.basename(f).split(".")
  if downloadType == "audio" or downloadType == "video" or downloadType == "music"
    output_path = "#{YTDL_OUTPUT_DIR}/#{downloadType}/#{videoType == "playlist" ? $playlist_fmt : ""}/%(channel)s__$__%(title)s__#__%(id)s.%(ext)s"
    format_code = downloadType == "video" ? $video_code : $audio_code
    merge_flag = downloadType == "video" ? "--merge-output-format mp4" : ""

    base_args = "-o '#{output_path}' #{$progress_flag} -f \"#{format_code}\" #{merge_flag}"
    success = run_ytdlp(base_args, ytid)

    system("mv \"#{Shellwords.escape f}\" ~/.Trash/") if success
    out_dir = "#{YTDL_OUTPUT_DIR}/#{downloadType}"
    # Find all .mp4 files that don't have corresponding .m4a files
    Dir.glob("#{out_dir}/*.mp4").each do |mp4_file|
      m4a_file = mp4_file.sub(/\.mp4$/, '.m4a')
      unless File.exist?(m4a_file)
        system("ffmpeg -i #{Shellwords.escape mp4_file} #{Shellwords.escape m4a_file} \
               && mv #{Shellwords.escape mp4_file} ~/.Trash/")
      end
    end
  else
    out_file = "#{YTDL_OUTPUT_DIR}/#{downloadType}/%(channel)s__$__%(title)s__#__%(id)s.%(ext)s"
    base_args = "-o '#{out_file}' --skip-download --write-subs --write-auto-subs --sub-langs en --convert-subs srt #{$progress_flag}"
    run_ytdlp(base_args, ytid)
    out_dir = "#{YTDL_OUTPUT_DIR}/#{downloadType}"

    # Check if any .srt files were created for this video
    srt_files = Dir.glob("#{out_dir}/*__#__#{ytid}.*.srt")

    if srt_files.empty?
      # No subtitles available, download audio and transcribe
      audio_file = "#{out_dir}/%(channel)s__$__%(title)s__#__%(id)s.%(ext)s"
      base_args = "-o '#{audio_file}' #{$progress_flag} -f \"#{$audio_code}\""
      run_ytdlp(base_args, ytid)

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
