require 'music/music_db.rb'

module MusicCMD

  def show(opts)
    opts.banner = "Usage: show [OPTS] ITEM"
    opts.info = "Look up a song in the DB and print its full record"
    opts.separator "    ITEM is matched against the field specified by --filter (default: .id, i.e. UUID)."
    opts.separator "    Returns all songs where FILTER == ITEM, printed as Ruby hashes."
    opts.separator ""
    opts.separator "    Examples:"
    opts.separator "      music show 3F2504E0-4F89-11D3-9A0C-0305E82C3301"
    opts.separator "      music show 'My Playlist' -f .playlist"
    opts.separator ""
    opts.on("-y", "--yt-search", "print the artist and name") { |field|
      $options[:yt_search] = true
    }
    opts.on("-f", "--filter FILTER", "Any string that `jq` will accept -- default: '.id'") { |jqf|
      $options[:filter] = jqf
    }
    lambda { |item|
      $options[:filter] = ".id" if not $options[:filter]
      MusicDB.select(item.gsub(/\..*$/, ""), $options[:filter]).each { |x|
        if $options[:yt_search]
          puts "#{x["artist"]} - #{x["name"]}".gsub(/ /, "+")
        else
          pp x
        end
      }
    }
  end

end
