require 'music/music_db.rb'

module MusicCMD

  def tag_from_db(opts)
    opts.banner = "Usage: tag_from_db [OPTIONS]"
    opts.info = "Sync file metadata from DB (re-tag files that have tags in DB)"
    opts.separator ""
    opts.on("-w", "--workers N", Integer, "Parallel workers (default: 4)") { |w|
      $options[:workers] = w
    }
    opts.on("--tags-only", "Only process songs that have tags field set") {
      $options[:tags_only] = true
    }

    lambda {
      workers = $options[:workers] || 4
      music = MusicDB.read

      songs = music.values
      if $options[:tags_only]
        songs = songs.select { |s| s["tags"] && !s["tags"].empty? }
      end

      puts "Found #{songs.length} songs to process"

      if songs.any? && !$options[:dry_run]
        log_dir = File.expand_path("~/.log")
        puts "Tagging #{songs.length} files with #{workers} workers..."
        MusicDB.tag songs, workers: workers, log_dir: log_dir
      elsif $options[:dry_run]
        puts "[Dry run] Would tag #{songs.length} files"
      else
        puts "No songs to process"
      end
    }
  end

end
