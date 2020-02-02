#!/usr/bin/env ruby

require "optparse"

module MusicCMD

  def cruft_opts()
    OptionParser.new do |opts|
      opts.banner = "Usage: cruft"
      opts.info = "Print any non db/music files present in the $MUSIC_DIR"
    end
  end

  def cruft()
    puts %x[ find $MUSIC_DIR -type f -not -name '.*' -not -regex '[\/0-9A-Za-z\-]*\.m4a' ]
  end

end
