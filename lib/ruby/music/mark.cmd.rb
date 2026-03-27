require 'music/music_db.rb'

module MusicCMD

  def mark(opts)
    opts.banner = "Usage: mark -s SONG_ID [-t TEXT]"
    opts.info = "Set a free-text mark/note on a song"
    opts.separator "    Without -t, prompts interactively for the mark text."
    opts.separator "    With -t, sets the mark non-interactively (suitable for scripting/AI)."
    opts.separator "    SONG_ID is a UUID or filename (extension stripped)."
    opts.separator ""
    opts.separator "    Example: music mark -s 3F2504E0-... -t 'needs re-tagging'"
    opts.separator ""
    opts.on("-s", "--song-id SONG_ID", "Apply the mark to SONG_ID") { |id|
      $options[:song_id] = id
    }
    opts.on("-t", "--text TEXT", "Mark it with the supplied TEXT") { |text|
      $options[:text] = text
    }
    lambda {
      song_id = $options[:song_id]
      raise "NEED SONG ID" if not song_id
      song_id = song_id.gsub(/\..*$/, "")
      p song_id if $options[:verbose]
      music = MusicDB.read
      song = music[song_id]
      p song if $options[:verbose]
      puts "#{song["playlist"]} | #{song["artist"]} - #{song["name"]}" if not $options[:verbose]
      p $options if $options[:verbose]
      song["marked"] =
        if $options[:text] then
          $options[:text]
        else
          RbReadline.prefill_prompt song["marked"] if song["marked"]
          Readline.readline("marked>?:".reverse).chomp
        end
      MusicDB.save music, song_id
    }
  end

end
