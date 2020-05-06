require 'music/music_db.rb'

module MusicCMD

  def search_impl(args = "")
    puts "CMD[SEARCH]" if $options[:verbose]
    puts "search: #{$options[:filter]}" if $options[:verbose]
    tmp = Tempfile.new; IO.write tmp, MusicDB.read($options[:filter])
    %x< cat '#{tmp.path}' | sort | uniq | zsh -ic 'search #{args}' >.gsub(/\]7;.*/, "")
  end

  def search(opts)
    opts.banner = "Usage: search [OPTS]"
    opts.info = "Search the music db, only prints selected"
    opts.on("-f", "--filter FILTER",
            "Any string that `jq` will accept -- default: '\"\\(.playlist) - \\(.name)\"'") { |jqf|
      $options[:filter] = jqf
    }
    lambda {
      $options[:filter] = '"\(.playlist) - \(.name)"' if not $options[:filter]
      puts search_impl()
    }
  end

end
