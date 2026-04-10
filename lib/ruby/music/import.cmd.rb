require 'music/music_db.rb'

module MusicCMD

  def import_ytdl(opts)
    opts.banner = "Usage: import_ytdl"
    opts.info = "Import all music from ~/Downloads/ytdl/music/ (interactive)"
    opts.separator "    Expects files named: <artist>__$__<title>__#__<yt-id>.m4a"
    opts.separator "    Top-level files get playlist 'TODO'; files in subdirs use dir name as playlist."
    opts.separator "    Prompts for artist/name confirmation per file."
    opts.separator ""
    lambda { ||
      Dir.chdir("#{%x[echo $HOME].strip}/Downloads/ytdl/music") {
        files = Dir["*"].filter(&File.method(:file?))
        _import_files({:playlist => "TODO"}, files)
        Dir["*"].reject(&File.method(:file?)).each { |folder|
          options = {:playlist => folder}
          _import_files(options, Dir["#{folder}/*"])
        }
      }
    }
  end


  def import(opts)
    opts.banner = "Usage: import [OPTS] FILES..."
    opts.info = "Import files into $MUSIC_CATALOG & $MUSIC_LIBRARY (interactive, prompts per file)"
    opts.on("-p", "--playlist PLAYLIST_NAME", "String to use as FILES's PLAYLIST metadata") { |pl|
      $options[:playlist] = pl
    }
    opts.on("-a", "--artist ARTIST", "String to use as FILES's ARTIST metadata") { |pl|
      $options[:artist] = pl
    }
    lambda { |*files|
      _import_files($options, files)
    }
  end

  def import_single(opts)
    opts.banner = "Usage: import_single -a ARTIST -t TITLE -p PLAYLIST FILE"
    opts.info = "Import one file into $MUSIC_CATALOG & $MUSIC_LIBRARY (non-interactive, scriptable)"
    opts.separator "    All metadata is specified via flags — no prompts. Ideal for scripting/AI."
    opts.separator "    Generates a UUID, moves the file to $MUSIC_LIBRARY/<uuid>.m4a, and tags it."
    opts.separator ""
    opts.separator "    Example: music import_single -a 'Artist' -t 'Title' -p 'Playlist' song.m4a"
    opts.separator ""
    opts.on("-p", "--playlist PLAYLIST_NAME", "(Required) String to use as FILE's PLAYLIST metadata") { |pl|
      $options[:playlist] = pl
    }
    opts.on("-a", "--artist ARTIST", "(Required) String to use as FILE's ARTIST metadata") { |artist|
      $options[:artist] = artist
    }
    opts.on("-t", "--title TITLE", "(Required) String to use as FILE's TITLE metadata") { |title|
      $options[:title] = title
    }
    lambda { |file|
      unless $options[:artist] && $options[:title] && $options[:playlist]
        puts "Error: --artist and --title are required"
        exit 1
      end
      _import_single_file($options, file)
    }
  end

  def _import_files(options, files)
      num_files = files.count
      files.each_with_index { |f, idx|
        puts ">>> ##{idx+1}/#{num_files} => #{f}".reverse
        sanitized = %x[basename #{Shellwords.escape f}].gsub(/[^\w\$\-\#\.\(\)\&\[\]\,\;\'\" ]/, "")
        yt_id = sanitized[/(.*)__\$__(.*)__#__([^\.]+)\.m4a/, 3]
        title = sanitized[/(.*)__\$__(.*)__#__([^\.]+)\.m4a/, 2]
        if options[:artist] then
          artist = options[:artist]
        else
          RbReadline.prefill_prompt title
          artist = Readline.readline("artist>?:".reverse).chomp
        end
        RbReadline.prefill_prompt title
        name = Readline.readline("name>?:".reverse).chomp
        uuid = %x[uuidgen].strip
        song = {:from => :ytdl,
                :id => uuid,
                :playlist => options[:playlist],
                :url => yt_id,
                :artist => artist,
                :name => name}
        p song if options[:verbose]
        if not options[:dry_run] then
          MusicDB.append song
          execute("cp #{Shellwords.escape f} $MUSIC_LIBRARY/#{uuid}.m4a && trash #{Shellwords.escape f}")
          MusicDB.tag([{"id" => uuid,
                        "artist" => artist,
                        "name" => name,
                        "playlist" => options[:playlist]}])
        end
      }
  end

  def _import_single_file(options, file)
    sanitized = %x[basename #{Shellwords.escape file}].gsub(/[^\w\$\-\#\.\(\)\&\[\]\,\;\'\" ]/, "")
    yt_id = sanitized[/(.*)__\$__(.*)__#__([^\.]+)\.m4a/, 3]

    artist = options[:artist]
    name = options[:title]
    playlist = options[:playlist]

    uuid = %x[uuidgen].strip
    song = {:from => :ytdl,
            :id => uuid,
            :playlist => playlist,
            :url => yt_id,
            :artist => artist,
            :name => name}

    p song if options[:verbose]

    if not options[:dry_run] then
      MusicDB.append song
      execute("cp #{Shellwords.escape file} $MUSIC_LIBRARY/#{uuid}.m4a && trash #{Shellwords.escape file}")
      MusicDB.tag([{"id" => uuid,
                    "artist" => artist,
                    "name" => name,
                    "playlist" => playlist}])
    end

    puts "Imported: #{name} by #{artist} (#{uuid})"
  end

end
