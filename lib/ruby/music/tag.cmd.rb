require 'music/music_db.rb'

module MusicCMD

  def tag(opts)
    opts.banner = "Usage: tag [-s SONG_ID] TAGS*"
    opts.info = "Tag SONG_ID with TAGS"
    opts.separator "    SONG_ID: Song \"id\" or filename"
    opts.separator "    TAGS format: <tag>[, <tag>]*"
    opts.separator ""
    opts.on("-s", "--song-id SONG_ID", "Required: Apply the mark to SONG_ID") { |id|
      $options[:song_id] = id
    }

    lambda { |*tag_args|
      song_id = $options[:song_id]
      raise "NEED SONG ID" if not song_id
      raise "NEED TAGS" if not tag_args

      song_id = song_id.gsub(/\..*$/, "")
      p song_id if $options[:verbose]
      music = MusicDB.read
      song = music[song_id]
      p song if $options[:verbose]
      puts "#{song["playlist"]} | #{song["artist"]} - #{song["name"]}" if not $options[:verbose]

      p $options if $options[:verbose]
      tags = tag_args.map {|s| s.gsub(/^,/, "").gsub(/,$/, "")}
      p tags if $options[:verbose]
      (song["tags"] ||= []).concat(tags)
      song["tags"] = song["tags"].uniq
      p song["tags"]
      MusicDB.save music, song_id if not $options[:dry_run]
      MusicDB.tag [song]
    }
  end

end
