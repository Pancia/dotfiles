require 'music/music_db.rb'

module MusicCMD

  def fix_metadata(opts)
    opts.banner = "Usage: fix_metadata FILE"
    opts.info = "Re-tag files listed in FILE with metadata from the DB"
    opts.separator "    FILE contains one .m4a path per line. Looks up each in the DB and re-writes metadata."
    opts.separator ""
    lambda { |file|
      $options[:verbose] = true
      db = MusicDB.read()
      entries = File.read(file).split.map {|f|
        puts f
        system("ffprobe #{f} 2>&1 | ag '^\s+(artist|album|title)'")
        entry = db["#{File.basename f, File.extname(f)}"]
        p entry
        entry
      }
      MusicDB.tag entries
    }
  end

  def fix_album(opts)
    opts.banner = "Usage: fix_album FILE"
    opts.info = "Rename playlists listed in FILE and re-tag their files (interactive)"
    opts.separator "    FILE contains one playlist name per line. Prompts for a new name for each."
    opts.separator ""
    lambda { |file|
      $options[:verbose] = true
      db = MusicDB.read()
      entries = File.read(file).split.map {|album|
        puts album
        album_songs = MusicDB.select(album, ".playlist")
        puts "new name?"
        new_name = STDIN.gets.chomp
        puts new_name
        album_songs.each { |entry|
          db[entry["id"]]["playlist"] = new_name
        }
        MusicDB.tag(album_songs.map{|entry| entry["playlist"] = new_name; entry})
      }
      MusicDB.save(db)
    }
  end

  def mtag(opts)
    opts.banner = "Usage: mtag [OPTS] ITEM"
    opts.info = "Write DB metadata into .m4a file tags via ffmpeg (DB -> file sync)"
    opts.separator "    Reads song data from $MUSIC_CATALOG and writes artist/title/album/genre"
    opts.separator "    into the file's embedded metadata. Only updates fields that differ."
    opts.separator "    ITEM is matched against --filter field (default: .id) to find songs."
    opts.separator ""
    opts.on("-n", "--dry-run", "Do not tag, just print") {
      $options[:dry_run] = true
    }
    opts.on("-f", "--filter FILTER", "Any string that `jq` will accept") { |jqf|
      $options[:filter] = jqf
    }
    opts.on("-s", "--select SELECT", "Any string that `jq` will accept") { |select|
      $options[:select] = select
    }
    lambda { |item|
      $options[:filter] = ".id" if not $options[:filter]
      if $options[:select]
        MusicDB.tag MusicDB.select_raw($options[:select])
      elsif
        MusicDB.tag MusicDB.select(item.gsub(/\..*$/, ""), $options[:filter])
      end
    }
  end

end
