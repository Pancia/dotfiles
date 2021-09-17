require 'music/music_db.rb'

module MusicCMD

  def import(opts)
    opts.banner = "Usage: import FILES"
    opts.info = "Imports files into $MUSIC_DB & $MUSIC_DIR"
    opts.on("-p", "--playlist PLAYLIST_NAME", "String to use as FILES's PLAYLIST metadata") { |pl|
      $options[:playlist] = pl
    }
    opts.on("-a", "--artist ARTIST", "String to use as FILES's ARTIST metadata") { |pl|
      $options[:artist] = pl
    }
    lambda { |*files|
      num_files = files.count
      files.each_with_index { |f, idx|
        puts ">>> ##{idx+1}/#{num_files} => #{f}".reverse
        sanitized = %x[basename #{Shellwords.escape f}].gsub(/[^\w\-\#\.\(\)\&\[\]\,\;\'\" ]/, "")
        yt_id = sanitized[/(.*)__#__([^\.]+)\.m4a/, 2]
        title = sanitized[/(.*)__#__([^\.]+)\.m4a/, 1]
        if $options[:artist] then
          artist = $options[:artist]
        else
          RbReadline.prefill_prompt title
          artist = Readline.readline("artist>?:".reverse).chomp
        end
        RbReadline.prefill_prompt title
        name = Readline.readline("name>?:".reverse).chomp
        uuid = %x[uuidgen].strip
        song = {:from => :ytdl,
                :id => uuid,
                :playlist => $options[:playlist],
                :url => yt_id,
                :artist => artist,
                :name => name}
        p song if $options[:verbose]
        if not $options[:dry_run] then
          MusicDB.append song
          execute("mv #{Shellwords.escape f} $MUSIC_DIR/#{uuid}.m4a")
          MusicDB.tag([{"id" => uuid,
                        "artist" => artist,
                        "name" => name,
                        "playlist" => $options[:playlist]}])
        end
      }
    }
  end

end
