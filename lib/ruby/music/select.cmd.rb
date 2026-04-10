require 'music/music_db.rb'
require 'music/search.cmd.rb'

module MusicCMD

  def select(opts)
    opts.banner = "Usage: select [OPTS]"
    opts.info = "Search DB interactively and queue selected songs in cmus for playback"
    opts.separator "    Opens fzf to pick items, then clears the cmus playlist and adds matching files."
    opts.separator "    --filter controls what field is searched/displayed (default: .playlist)."
    opts.separator ""
    opts.on("-f", "--filter FILTER", "jq field expression to group/display by (default: .playlist)") { |jqf|
      $options[:filter] = jqf
    }
    opts.on("-t", "--filter-by-tags", "Filter by tags") {
      $options[:filter] = "select(.tags) | .tags / \",\" | .[]"
    }
    lambda {
      $options[:filter] = ".playlist" if not $options[:filter]
      result = self._search_impl()
      return if result.nil? || result.strip.empty?
      items = result.split("\n").reject { |item| item.strip.empty? }
      p "items: #{items}" if $options[:verbose]
      if not items.empty?
        system("cmus-remote --clear")
        items.each do |item|
          files = MusicDB.find item, $options[:filter]
          files.split("\n").each do |f|
            system("cmus-remote $MUSIC_LIBRARY/#{f}")
          end
        end
        system("cmus-remote --raw 'view playlist'")
        system("cmus-remote --raw 'win-activate'")
      end
    }
  end

end
