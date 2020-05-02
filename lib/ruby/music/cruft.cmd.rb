module MusicCMD

  def cruft(opts)
    opts.banner = "Usage: cruft"
    opts.info = "Print any non db/music files present in the $MUSIC_DIR"
    lambda {
      puts %x[ find $MUSIC_DIR -type f -not -name '.*' -not -regex '[\/0-9A-Za-z\-]*\.m4a' ]
    }
  end

end
