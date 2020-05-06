require 'music/music_db.rb'

module MusicCMD

  def show(opts)
    opts.banner = "Usage: show [OPTS] ITEM"
    opts.info = "Show the items info wrt the music db"
    opts.separator "    ITEM: String, will be compared in `jq` to FILTER"
    opts.separator ""
    opts.on("-f", "--filter FILTER", "Any string that `jq` will accept -- default: '.id'") { |jqf|
      $options[:filter] = jqf
    }
    lambda { |item|
      $options[:filter] = ".id" if not $options[:filter]
      MusicDB.select(item.gsub(/\..*$/, ""), $options[:filter]).each { |x| pp x }
    }
  end

end
