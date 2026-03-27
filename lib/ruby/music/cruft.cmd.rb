module MusicCMD

  def cruft(opts)
    opts.banner = "Usage: cruft"
    opts.info = "List files in $MUSIC_DIR that aren't tracked in the DB"
    opts.separator "    Prints paths of files that don't match the <uuid>.m4a naming pattern."
    opts.separator "    Useful for finding orphaned downloads, temp files, or unimported music."
    opts.separator ""
    lambda {
      puts %x[ find $MUSIC_DIR -type f -not -name '.*' -not -regex '[\/0-9A-Za-z\-]*\.m4a' ]
    }
  end

end
