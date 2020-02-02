#!/usr/bin/env ruby

require "optparse"
require 'music_db.rb'

module MusicCMD

  def show_opts()
    OptionParser.new do |opts|
      opts.banner = "Usage: show [OPTS] ITEM"
      opts.info = "Show the items info wrt the music db"
      opts.separator "    ITEM: String, will be compared in `jq` to FILTER"
      opts.separator ""
      $options[:filter] = ".id"
      opts.on("-f", "--filter FILTER", "Any string that `jq` will accept -- default: '.id'") { |jqf|
        $options[:filter] = jqf
      }
    end
  end

  def show(item)
    MusicDB.select(item.gsub(/\..*$/, ""), $options[:filter]).each { |x| pp x }
  end

end
