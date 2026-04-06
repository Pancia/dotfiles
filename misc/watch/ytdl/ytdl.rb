# Processes .ytdl trigger files from ~/Downloads by delegating to bin/ytdl.
# Trigger filename format: <id>.<single|playlist>.<type>.ytdl

YTDL_BIN = File.expand_path("~/dotfiles/bin/ytdl")
YTDL_DOWNLOADS_DIR = File.expand_path("~/Downloads")

files = Dir["#{YTDL_DOWNLOADS_DIR}/*.ytdl"]
if files.empty?
  print "∙"
  exit 0
end

system("echo;date")

files.each do |f|
  ytid, video_type, download_type, _ = File.basename(f).split(".")

  # Build the URL/ID to pass to bin/ytdl
  url = if video_type == "playlist"
    "https://www.youtube.com/playlist?list=#{ytid}"
  else
    ytid
  end

  puts "=== Processing: #{File.basename(f)} ==="
  success = system(YTDL_BIN, "--quiet", download_type, url)

  if success
    system("trash", f)
  else
    puts "[FAILED] #{File.basename(f)}"
  end
end
