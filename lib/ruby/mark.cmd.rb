#!/usr/bin/env ruby

require "optparse"
require 'music_db.rb'

module MusicCMD

  def mark_opts()
    OptionParser.new do |opts|
      opts.banner = "Usage: mark [-s SONG_ID] [-t TEXT]"
      opts.info = "Mark SONG_ID with TEXT or user supplied from stdin"
      opts.separator "    SONG_ID: Song \"id\" or filename"
      opts.separator "    TEXT: string to mark SONG_ID with"
      opts.separator ""
      $options[:song_id] = nil
      opts.on("-s", "--song-id SONG_ID", "Apply the mark to SONG_ID") { |id|
        $options[:song_id] = id
      }
      $options[:text] = nil
      opts.on("-t", "--text TEXT", "Mark it with the supplied TEXT") { |text|
        $options[:text] = text
      }
    end
  end

  def mark()
    song_id = $options[:song_id]
    raise "NEED SONG ID" if not song_id
    song_id = song_id.gsub(/\..*$/, "")
    p song_id if $options[:verbose]
    music = MusicDB.read
    song = music[song_id]
    p song if $options[:verbose]
    puts "#{song["playlist"]} | #{song["artist"]} - #{song["name"]}" if not $options[:verbose]

    p $options if $options[:verbose]
    song["marked"] =
      if $options[:text] then
        $options[:text]
      else
        RbReadline.prefill_prompt song["marked"] if song["marked"]
        Readline.readline("marked>?:".reverse).chomp
      end
    MusicDB.save music, song_id
  end

end
