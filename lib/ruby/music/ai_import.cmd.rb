require 'music/music_db.rb'
require 'json'
require 'tempfile'
require 'set'
require 'net/http'
require 'uri'
require 'shellwords'

module MusicCMD

  YTDL_MUSIC_DIR = ENV['MUSIC_INBOX'] || File.expand_path("~/Cloud/ytdl/music")
  SYNCTHING_CONFIG = File.expand_path("~/Library/Application Support/Syncthing/config.xml")
  SYNCTHING_PORT = 8384

  def ai_import(opts)
    opts.banner = "Usage: ai_import [OPTS]"
    opts.info = "AI-powered import from ytdl music inbox (preview table + approval)"
    opts.separator "    Scans ~/Cloud/ytdl/music for .m4a files, uses Claude to parse"
    opts.separator "    artist/title from filenames, shows a table for approval, and imports."
    opts.separator "    Triggers Syncthing rescan of the music folder when done."
    opts.separator ""
    opts.on("-p", "--playlist PLAYLIST", "Playlist name (default: TODO)") { |pl|
      $options[:playlist] = pl
    }
    opts.on("-d", "--dir DIR", "Directory to scan (default: ~/Cloud/ytdl/music)") { |d|
      $options[:dir] = d
    }
    lambda {
      _ai_import($options)
    }
  end

  def _ai_import(options)
    dir = options[:dir] || YTDL_MUSIC_DIR
    playlist = options[:playlist] || "TODO"

    unless Dir.exist?(dir)
      puts "Error: directory not found: #{dir}"
      exit 1
    end

    # 1. Scan for .m4a files
    files = Dir["#{dir}/*.m4a"].sort
    if files.empty?
      puts "No .m4a files found in #{dir}"
      return
    end
    puts "Found #{files.size} file(s) in #{dir}\n\n"

    # 2. Parse filenames into structured data
    entries = files.filter_map { |f| _parse_ytdl_filename(f) }
    if entries.empty?
      puts "No files matched the expected filename pattern."
      return
    end

    # 3. Check DB for already-imported YouTube IDs
    db = MusicDB.read
    existing_urls = Set.new(db.values.map { |s| s["url"] }.compact)

    new_entries, dupes = entries.partition { |e| !existing_urls.include?(e[:yt_id]) }

    if dupes.any?
      puts "\e[33mAlready imported (#{dupes.size}):\e[0m"
      dupes.each { |e| puts "  \e[33m#{e[:yt_id]}\e[0m #{e[:channel]} — #{e[:raw_title]}" }
      puts ""
    end

    if new_entries.empty?
      puts "Nothing new to import."
      return
    end

    # 4. Ask Claude to parse filenames into artist/title (skip in dry-run)
    suggestions = []
    unless options[:dry_run]
      puts "Asking Claude to parse #{new_entries.size} filename(s)...\n\n"
      suggestions = _ai_parse_filenames(new_entries)
    end

    # 5. Build table rows
    table = new_entries.each_with_index.map { |e, i|
      s = suggestions[i] || {}
      {
        idx: i,
        file: e[:file],
        yt_id: e[:yt_id],
        channel: e[:channel],
        raw_title: e[:raw_title],
        artist: s["artist"] || e[:channel],
        title: s["title"] || e[:raw_title],
        playlist: playlist,
        skip: false,
      }
    }

    # 6. Interactive approval loop
    _display_table(table)
    _interactive_edit(table)

    # 7. Import approved rows
    to_import = table.reject { |r| r[:skip] }
    if to_import.empty?
      puts "Nothing to import."
      return
    end

    puts "\nImporting #{to_import.size} track(s)...\n\n"
    imported = 0
    to_import.each do |row|
      $options[:artist] = row[:artist]
      $options[:title] = row[:title]
      $options[:playlist] = row[:playlist]
      _import_single_file($options, row[:file])
      imported += 1
    end

    puts "\n\e[32mImported #{imported} track(s).\e[0m\n\n"

    # 8. Trigger Syncthing rescan
    _syncthing_rescan
  end

  def _parse_ytdl_filename(filepath)
    basename = File.basename(filepath)
    m = basename.match(/^(.*)__\$__(.*)__#__([^\.]+)\.m4a$/)
    return nil unless m
    { file: filepath, channel: m[1], raw_title: m[2], yt_id: m[3] }
  end

  def _ai_parse_filenames(entries)
    descriptions = entries.map { |e|
      "#{e[:channel]}__$__#{e[:raw_title]}__#__#{e[:yt_id]}.m4a"
    }

    prompt = <<~PROMPT
      Parse these YouTube music filenames into artist and title metadata.
      The format is: channel__$__title__#__YTID.m4a

      The "channel" is the YouTube uploader (often not the real artist).
      The "title" is the YouTube video title (often has "artist - song" or extra junk like "(Official Video)", "slowed + reverb", etc.).

      For each file, extract the real artist name and clean song title.
      Keep "(slowed + reverb)" or "(remix)" etc. in the title if present — those are intentional variants.
      Strip things like "(Official Video)", "(Official Audio)", "(Lyrics)", "(Audio)", "ft." → "feat." normalization is fine.

      Return ONLY a JSON array (no markdown fences) with one object per file, in order:
      [{"artist": "...", "title": "..."}, ...]

      Filenames:
      #{descriptions.map { |d| "- #{d}" }.join("\n")}
    PROMPT

    json_str = `claude -p --model haiku --output-format json #{Shellwords.escape(prompt)} 2>/dev/null`

    begin
      result = JSON.parse(json_str)
      # --output-format json wraps in {"type":"result","result":"..."}
      if result.is_a?(Hash) && result["result"]
        inner = result["result"]
        # The inner result might be a JSON string or might have markdown fences
        inner = inner.gsub(/```json\s*/, '').gsub(/```\s*/, '').strip
        parsed = JSON.parse(inner)
        return parsed if parsed.is_a?(Array)
      end
      return result if result.is_a?(Array)
      []
    rescue JSON::ParserError => e
      puts "\e[31mWarning: Could not parse Claude response: #{e.message}\e[0m"
      puts "Raw response: #{json_str[0..200]}" if $options[:verbose]
      []
    end
  end

  def _display_table(table)
    # Column widths
    idx_w = 3
    artist_w = [table.map { |r| r[:artist].length }.max || 10, 30].min
    title_w = [table.map { |r| r[:title].length }.max || 10, 45].min
    playlist_w = [table.map { |r| r[:playlist].length }.max || 10, 20].min
    yt_w = 11

    header = " %-#{idx_w}s │ %-#{artist_w}s │ %-#{title_w}s │ %-#{playlist_w}s │ %-#{yt_w}s" %
             ["#", "Artist", "Title", "Playlist", "YT ID"]
    sep = "─" * (idx_w + 1) + "┼" + "─" * (artist_w + 2) + "┼" + "─" * (title_w + 2) +
          "┼" + "─" * (playlist_w + 2) + "┼" + "─" * (yt_w + 2)

    puts header
    puts sep
    table.each do |r|
      status = r[:skip] ? "\e[9m\e[90m" : ""  # strikethrough + dim if skipped
      reset = r[:skip] ? "\e[0m" : ""
      artist_s = r[:artist].length > artist_w ? r[:artist][0..artist_w-2] + "…" : r[:artist]
      title_s = r[:title].length > title_w ? r[:title][0..title_w-2] + "…" : r[:title]
      playlist_s = r[:playlist].length > playlist_w ? r[:playlist][0..playlist_w-2] + "…" : r[:playlist]

      puts "#{status} %-#{idx_w}d │ %-#{artist_w}s │ %-#{title_w}s │ %-#{playlist_w}s │ %-#{yt_w}s#{reset}" %
           [r[:idx] + 1, artist_s, title_s, playlist_s, r[:yt_id]]
    end
    puts ""
  end

  def _interactive_edit(table)
    loop do
      print "\e[36m[a]ccept | [e]dit N | [v]im | [p]laylist N | [s]kip N | [r]eshow | [q]uit\e[0m > "
      input = $stdin.gets&.strip
      return if input.nil?

      case input
      when "a", "y", ""
        puts "\e[32mAccepted.\e[0m"
        return
      when "q"
        table.each { |r| r[:skip] = true }
        puts "Aborted — all skipped."
        return
      when "v"
        _vim_edit(table)
        _display_table(table)
      when "r"
        _display_table(table)
      when /^s\s+(\d+)$/
        n = $1.to_i - 1
        if n >= 0 && n < table.size
          table[n][:skip] = !table[n][:skip]
          status = table[n][:skip] ? "\e[33mskipped\e[0m" : "\e[32munskipped\e[0m"
          puts "  #{n + 1}. #{table[n][:artist]} — #{table[n][:title]}: #{status}"
        else
          puts "  Invalid row number."
        end
      when /^e\s+(\d+)$/
        n = $1.to_i - 1
        if n >= 0 && n < table.size
          row = table[n]
          puts "  Editing row #{n + 1}: #{row[:artist]} — #{row[:title]}"

          print "  artist [#{row[:artist]}]: "
          a = $stdin.gets&.strip
          row[:artist] = a unless a.nil? || a.empty?

          print "  title  [#{row[:title]}]: "
          t = $stdin.gets&.strip
          row[:title] = t unless t.nil? || t.empty?

          row[:skip] = false
          puts "  \e[32mUpdated.\e[0m"
        else
          puts "  Invalid row number."
        end
      when /^p\s+(\d+)$/
        n = $1.to_i - 1
        if n >= 0 && n < table.size
          row = table[n]
          print "  playlist [#{row[:playlist]}]: "
          p = $stdin.gets&.strip
          row[:playlist] = p unless p.nil? || p.empty?
          puts "  \e[32mUpdated.\e[0m"
        else
          puts "  Invalid row number."
        end
      when /^p\s+(.+)$/
        # Set playlist for all rows: "p My Playlist"
        new_pl = $1.strip
        table.each { |r| r[:playlist] = new_pl }
        puts "  \e[32mPlaylist set to '#{new_pl}' for all rows.\e[0m"
      else
        puts "  Unknown command. Try: a, e N, p N, s N, r, q"
      end
    end
  end

  def _vim_edit(table)
    tmpfile = Tempfile.new(["ai_import_edit", ".txt"])
    begin
      tmpfile.puts "# Edit fields. Comment out a line (#) to skip it."
      tmpfile.puts "# ROW -$- ARTIST -@- TITLE -#- PLAYLIST"
      table.each do |row|
        line = "#{row[:idx] + 1} -$- #{row[:artist]} -@- #{row[:title]} -#- #{row[:playlist]}"
        line = "# #{line}" if row[:skip]
        tmpfile.puts line
      end
      tmpfile.close

      unless system(ENV.fetch("EDITOR", "vim"), tmpfile.path)
        puts "  \e[33mEditor exited with error — no changes applied.\e[0m"
        return
      end

      seen = Set.new
      File.readlines(tmpfile.path).each do |line|
        line = line.strip
        next if line.empty?
        next if line.start_with?("# ROW -$-") || line == "# Edit fields. Comment out a line (#) to skip it."

        skipped = false
        if line.start_with?("#")
          skipped = true
          line = line.sub(/^#\s*/, "")
        end

        parts = line.split(/\s*-\$-\s*|\s*-@-\s*|\s*-#-\s*/)
        unless parts.size == 4
          puts "  \e[33mSkipping malformed line: #{line[0..60]}\e[0m"
          next
        end

        n = parts[0].to_i - 1
        unless n >= 0 && n < table.size
          puts "  \e[33mSkipping invalid row number: #{parts[0]}\e[0m"
          next
        end

        seen << n
        table[n][:artist] = parts[1]
        table[n][:title] = parts[2]
        table[n][:playlist] = parts[3]
        table[n][:skip] = skipped
      end

      puts "  \e[32mUpdated #{seen.size} row(s) from editor.\e[0m"
    ensure
      tmpfile.unlink
    end
  end

  def _syncthing_rescan
    puts "Triggering Syncthing rescan..."

    # Read API key from Syncthing config
    api_key = nil
    folder_id = nil
    if File.exist?(SYNCTHING_CONFIG)
      config = File.read(SYNCTHING_CONFIG)
      api_key = config[/<apikey>([^<]+)<\/apikey>/, 1]
      # Find the music folder ID
      config.scan(/<folder id="([^"]+)"[^>]*label="([^"]*)"[^>]*path="([^"]*)"/) do |id, label, path|
        if label.downcase == "music" || path.include?("music")
          folder_id = id
          break
        end
      end
    end

    unless api_key
      puts "\e[33mWarning: Could not read Syncthing API key. Skipping rescan.\e[0m"
      return
    end

    begin
      uri = URI("http://127.0.0.1:#{SYNCTHING_PORT}/rest/db/scan")
      uri.query = "folder=#{folder_id}" if folder_id
      req = Net::HTTP::Post.new(uri)
      req["X-API-Key"] = api_key
      res = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }

      if res.code.to_i == 200
        target = folder_id ? "folder '#{folder_id}'" : "all folders"
        puts "\e[32mSyncthing rescan triggered for #{target}.\e[0m"
      else
        puts "\e[33mSyncthing rescan returned HTTP #{res.code}: #{res.body}\e[0m"
      end
    rescue => e
      puts "\e[33mWarning: Could not trigger Syncthing rescan: #{e.message}\e[0m"
    end

    # Also rescan the music DB folder (ProtonDrive/Music)
    if File.exist?(SYNCTHING_CONFIG)
      config = File.read(SYNCTHING_CONFIG)
      config.scan(/<folder id="([^"]+)"[^>]*label="([^"]*)"[^>]*path="([^"]*)"/) do |id, label, path|
        if path.include?("ProtonDrive/Music") || path.include?("ProtonDrive/music")
          begin
            uri2 = URI("http://127.0.0.1:#{SYNCTHING_PORT}/rest/db/scan")
            uri2.query = "folder=#{id}"
            req2 = Net::HTTP::Post.new(uri2)
            req2["X-API-Key"] = api_key
            Net::HTTP.start(uri2.hostname, uri2.port) { |http| http.request(req2) }
            puts "\e[32mSyncthing rescan triggered for DB folder '#{id}'.\e[0m"
          rescue => e
            puts "\e[33mWarning: Could not rescan DB folder: #{e.message}\e[0m"
          end
          break
        end
      end
    end
  end

end
