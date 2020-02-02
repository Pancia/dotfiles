#!/usr/bin/env ruby

require "tempfile"
require "shellwords"

class MusicDB

  def self.save(music, temp_name = "")
    tmp = Tempfile.new temp_name
    p tmp.path if $options[:verbose]
    IO.write tmp, JSON.generate(music)
    %x[ cat #{tmp.path} | jq '.' > $MUSIC_DB ]
  end

  def self.append(song)
    puts "MusicDB.append: #{song}" if $options[:verbose]
    db = MusicDB.read
    db[song[:id]] = song
    MusicDB.save db, song[:id]
  end

  def self.read(filter = nil)
    if filter
      %x[ cat $MUSIC_DB | jq -r '.[] | #{filter}' ]
    else
      JSON.parse %x[ cat $MUSIC_DB | jq '.' ]
    end
  end

  def self.find(item, filter)
    %x< cat $MUSIC_DB | jq -r '.[] | select(#{filter} == $item) | "\\(.id).m4a"' --arg item "#{item}" >
  end

  def self.select(item, filter)
    JSON.parse %x[ cat $MUSIC_DB | jq '[.[] | select(#{filter} == $item)]' --arg item "#{item}" ]
  end

  @meta_to_db = {"artist"=>"artist", "title"=>"name", "album"=>"playlist"}

  def self.metadata(item)
    metadata = JSON.parse(%x[ ffprobe -v quiet -print_format json -show_format $MUSIC_DIR/#{item["id"]}.m4a])
    fmt = metadata.fetch("format", nil)
    return {} if not fmt
    return fmt["tags"]
  end

  def self.parse_tags(item)
    m = self.metadata(item)
    m == {} ? {} : m
      .map {|k, v| [@meta_to_db[k], v] }.to_h
      .select {|k,_| @meta_to_db.values.include? k}
  end

  def self.tag(items)
    items.each do |i|
      file_tags = self.parse_tags i
      item = i.select {|k,_| @meta_to_db.values.include? k}
      diff = hash_diff item, file_tags
      if not diff.empty?
        meta_str = diff.keys
          .map {|k| [" -metadata ", @meta_to_db.invert[k], "=", "#{item[k].shellescape}", " "]}
          .join ""
        if $options[:dry_run]
          puts meta_str
        else
          puts meta_str if $options[:verbose]
          file = i["id"]+".m4a"
          tmp = i["id"]+".tmp.m4a"
          log = i["id"]+".log.m4a"
          system("ffmpeg -v warning -i $MUSIC_DIR/#{file} #{meta_str} $MUSIC_DIR/#{tmp} 2>&1 | tee -a $MUSIC_DIR/#{log} && mv $MUSIC_DIR/#{tmp} $MUSIC_DIR/#{file}")
        end
      end
    end
  end

end
