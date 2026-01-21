require 'music/music_db.rb'

module MusicCMD

  def import_tags(opts)
    opts.banner = "Usage: import_tags [OPTIONS] FILE"
    opts.info = "Import tags from a file into $MUSIC_DB & music files"
    opts.separator "    FILE format: UUID -$- Artist -@- Title -#- tag1, tag2"
    opts.separator ""
    opts.on("-w", "--workers N", Integer, "Parallel workers for file tagging (default: 4)") { |w|
      $options[:workers] = w
    }
    opts.on("--db-only", "Only update JSON db, skip file metadata tagging") {
      $options[:db_only] = true
    }

    lambda { |file|
      workers = $options[:workers] || 4
      raise "File not found: #{file}" unless File.exist?(file)

      music = MusicDB.read
      updated = []

      File.readlines(file).each_with_index do |line, idx|
        line = line.strip
        next if line.empty?

        # Parse: UUID -$- Artist -@- Title -#- tag1, tag2
        match = line.match(/^([A-F0-9\-]+)\s+-\$-\s+(.+?)\s+-@-\s+(.+?)\s+-#-\s+(.+)$/i)
        unless match
          puts "Skipping line #{idx + 1}: invalid format"
          next
        end

        uuid, artist, title, tags_str = match.captures
        tags = tags_str.split(",").map(&:strip).reject(&:empty?)

        song = music[uuid]
        unless song
          puts "Skipping #{uuid}: not found in database"
          next
        end

        # Merge new tags with existing
        existing_tags = (song["tags"] || "").split(",").map(&:strip).reject(&:empty?)
        merged_tags = (existing_tags + tags).uniq.join(",")

        if merged_tags != song["tags"]
          song["tags"] = merged_tags
          updated << song
          puts "#{uuid}: #{song["artist"]} - #{song["name"]} => #{merged_tags}"
        else
          puts "#{uuid}: no new tags" if $options[:verbose]
        end
      end

      if updated.any? && !$options[:dry_run]
        MusicDB.save music, "import_tags"
        if $options[:db_only]
          puts "\nUpdated #{updated.count} songs in DB (skipped file tagging)"
        else
          log_dir = File.expand_path("~/.log")
          puts "\nTagging #{updated.count} files with #{workers} workers..."
          MusicDB.tag updated, workers: workers, log_dir: log_dir
        end
      elsif $options[:dry_run]
        puts "\n[Dry run] Would update #{updated.count} songs"
      else
        puts "\nNo songs needed updating"
      end
    }
  end

end
