require 'music/music_db.rb'

module MusicCMD

  def _search_impl(args = "")
    puts "CMD[SEARCH]" if $options[:verbose]
    puts "search: #{$options[:filter]}" if $options[:verbose]
    tmp = Tempfile.new; IO.write tmp, MusicDB.read($options[:filter])
    %x< cat '#{tmp.path}' | sort | uniq #{ "| fish -c 'search #{args}' " if not $options[:raw]} >.gsub(/\]7;.*/, "")
  end

  def search(opts)
    opts.banner = "Usage: search [OPTS]"
    opts.info = "Search the music DB interactively (fzf) or print all entries with --raw"
    opts.separator "    Without --raw, opens an interactive fuzzy finder to pick entries."
    opts.separator "    --filter controls the display format (a jq expression applied to each song)."
    opts.separator ""
    opts.separator "    Examples:"
    opts.separator "      music search --raw                         # print all 'playlist - name' lines"
    opts.separator "      music search --raw -f .artist              # print all artist names"
    opts.separator "      music search -f '.id'                      # pick by UUID interactively"
    opts.separator ""
    opts.on("-r", "--raw",
            "Print all results to stdout instead of opening interactive picker") { |jqf|
      $options[:raw] = true
    }
    opts.on("-f", "--filter FILTER",
            "jq expression for display format (default: '\"\\(.playlist) - \\(.name)\"')") { |jqf|
      $options[:filter] = jqf
    }
    lambda {
      $options[:filter] = '"\(.playlist) - \(.name)"' if not $options[:filter]
      puts _search_impl()
    }
  end

end
