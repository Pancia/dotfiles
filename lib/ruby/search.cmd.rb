#!/usr/bin/env ruby

require "optparse"
require 'music_db.rb'

module MusicCMD

  def search_opts()
    OptionParser.new do |opts|
      opts.banner = "Usage: search [OPTS]"
      opts.info = "Search the music db, only prints selected"
      $options[:filter] = '"\(.playlist) - \(.name)"'
      opts.on("-f", "--filter FILTER",
              "Any string that `jq` will accept -- default: '\"\\(.playlist) - \\(.name)\"'") { |jqf|
        $options[:filter] = jqf
      }
    end
  end

  def search_impl(opts = "")
    puts "CMD[SEARCH]" if $options[:verbose]
    puts "search: #{$options[:filter]}" if $options[:verbose]
    tmp = Tempfile.new; IO.write tmp, MusicDB.read($options[:filter])
    %x< cat '#{tmp.path}' | sort | uniq | zsh -ic 'search #{opts}' >.gsub(/\]7;.*/, "")
  end

  def search()
    puts search_impl()
  end

end
