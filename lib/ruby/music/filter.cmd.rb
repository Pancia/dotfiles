require 'music/music_db.rb'

module MusicCMD

  def filter(opts)
    opts.banner = "Usage: filter [OPTS]"
    opts.info = "Print all matching songs according to FILTER"
    opts.on("-f", "--filter FILTER", "A comma separated list of playlists") { |f|
      $options[:filter] = f
    }
    lambda {
      raise "--filter is required!" if not $options[:filter]
      mdb = MusicDB.read()
      pickme = $options[:filter].split(",")
      by_playlist = mdb.map{|_,x| x}.group_by{|x| x["playlist"]}
      by_playlist.select{|name, list| pickme.include?(name)}
        .values.flatten.map{|x| x["id"]}
        .each{|f| puts "#{f}.m4a"}
    }
  end

end
