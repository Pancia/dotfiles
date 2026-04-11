# Processes .ytdl trigger files from ~/Downloads by delegating to bin/ytdl.
# Trigger filename format: <id>.<single|playlist>.<type>.ytdl
# File contents (optional): JSON object with extra options, e.g. {"quality":"best"}

require "json"

YTDL_BIN = File.expand_path("~/dotfiles/bin/ytdl")
YTDL_DOWNLOADS_DIR = File.expand_path("~/Downloads")
YTDL_VALID_QUALITIES = %w[regular best].freeze

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

  # Parse optional JSON payload. Strict validation — any problem fails the job
  # and leaves the file in place (same policy as a failed download).
  opts = {}
  content = File.read(f).strip
  unless content.empty?
    begin
      opts = JSON.parse(content)
    rescue JSON::ParserError => e
      puts "[FAILED] #{File.basename(f)}: invalid JSON (#{e.message})"
      next
    end

    unless opts.is_a?(Hash)
      puts "[FAILED] #{File.basename(f)}: JSON must be an object"
      next
    end

    if opts.key?("quality") && !YTDL_VALID_QUALITIES.include?(opts["quality"])
      puts "[FAILED] #{File.basename(f)}: invalid quality '#{opts["quality"]}' (expected regular|best)"
      next
    end
  end

  args = ["--quiet"]
  args.push("--quality", opts["quality"]) if opts["quality"] && opts["quality"] != "regular"
  args.push(download_type, url)

  puts "=== Processing: #{File.basename(f)} ==="
  success = system(YTDL_BIN, *args)

  if success
    system("trash", f)
  else
    puts "[FAILED] #{File.basename(f)}"
  end
end
