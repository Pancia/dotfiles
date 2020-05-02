require 'music/music_db.rb'

module MusicCMD

  def import(opts)
    opts.banner = "Usage: import FILES"
    opts.info = "Imports files into $MUSIC_DB & $MUSIC_DIR"
    $options[:playlist] = nil
    opts.on("-p", "--playlist PLAYLIST_NAME", "String to use as FILES's PLAYLIST metadata") { |pl|
      $options[:playlist] = pl
    }
    lambda { |*files|
      num_files = files.count
      files.each_with_index { |f, idx|
        puts ">>> ##{idx+1}/#{num_files} => #{f}".reverse
        sanitized = %x[basename #{Shellwords.escape f}].gsub(/[^\w\-\#\.\(\)\&\[\]\,\;\'\" ]/, "")
        playlist = $options[:playlist] || %x[dirname #{Shellwords.escape f}].gsub(/\_/, " ").strip
        yt_id = sanitized[/(.*)__#__([^\.]+)\.m4a/, 2]
        title = sanitized[/(.*)__#__([^\.]+)\.m4a/, 1]
        RbReadline.prefill_prompt title
        artist = Readline.readline("artist>?:".reverse).chomp
        RbReadline.prefill_prompt title
        name = Readline.readline("name>?:".reverse).chomp
        uuid = %x[uuidgen].strip
        song = {:from => :ytdl,
                :id => uuid,
                :playlist => playlist,
                :url => yt_id,
                :artist => artist,
                :name => name}
        p song if $options[:dry_run] or $options[:verbose]
        MusicDB.append song if not $options[:dry_run]
        execute("mv #{Shellwords.escape f} $MUSIC_DIR/#{uuid}.m4a")
        MusicDB.tag([{"id" => uuid,
                      "artist" => artist,
                      "name" => name,
                      "playlist" => playlist}])
      }
    }
  end

end
