require 'music/music_db.rb'
require 'set'

module MusicCMD

  def filter(opts)
    opts.banner = "Usage: filter [OPTS]"
    opts.info = "Print filenames of songs matching a playlist or tag filter"
    opts.separator "    Outputs one <uuid>.m4a filename per line. Exactly one of -p or -t is required."
    opts.separator ""
    opts.separator "    Examples:"
    opts.separator "      music filter -p 'My Playlist'              # all songs in playlist"
    opts.separator "      music filter -p 'Jazz,Classical'           # songs in either playlist"
    opts.separator "      music filter -t 'chill,ambient'            # songs with either tag"
    opts.separator ""
    opts.on("-p", "--by-playlist PLAYLISTS", "Comma-separated list of playlist names to match") { |f| $options[:by_playlist] = f }
    opts.on("-t", "--by-tags TAGS", "Comma-separated list of tags to match (OR logic)") { |f| $options[:by_tags] = f }
    lambda {
      raise "a filter is required!" if not $options[:by_playlist] and not $options[:by_tags]
      raise "only one filter is allowed!" if $options[:by_playlist] and $options[:by_tags]
      mdb = MusicDB.read()
      if $options[:by_tags] then
        filter = $options[:by_tags].split(",")
        mdb.map{|_,x| x}.select{|x| not filter.to_set.intersection((x["tags"] or "").split(",").to_set).empty?}
          .map{|x| x["id"]}
          .each{|id| puts "#{id}.m4a"}
      else
        filter = $options[:by_playlist].split(",")
        by_playlist = mdb.map{|_,x| x}.group_by{|x| x["playlist"]}
        by_playlist.select{|name, list| filter.include?(name)}
          .values.flatten.map{|x| x["id"]}
          .each{|id| puts "#{id}.m4a"}
      end
    }
  end

end
