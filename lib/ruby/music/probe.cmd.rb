require 'music/music_db.rb'

module MusicCMD

  def probe(opts)
    opts.banner = "Usage: probe [OPTS] ITEM"
    opts.info = "Read current metadata embedded in the .m4a file (via ffprobe)"
    opts.separator "    Shows what's actually in the file, not what the DB says."
    opts.separator "    Useful for verifying file tags match DB after tagging."
    opts.separator "    ITEM is matched against --filter field (default: .id) to find songs."
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
