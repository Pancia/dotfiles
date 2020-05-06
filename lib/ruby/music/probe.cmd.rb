require 'music/music_db.rb'

module MusicCMD

  def probe(opts)
    opts.banner = "Usage: probe [OPTS] ITEM"
    opts.info = "Probe the file for its current metadata (uses: ffprobe)"
    opts.separator "    ITEM: String, will be compared in `jq` to FILTER"
    opts.separator ""
    opts.on("-f", "--filter FILTER", "Any string that `jq` will accept") { |jqf|
      $options[:filter] = jqf
    }
    lambda { |item|
      $options[:filter] = ".id" if not $options[:filter]
      MusicDB.select(item.gsub(/\..*$/, ""), $options[:filter]).each {|x| p MusicDB.metadata x}
    }
  end

end
