require "json"
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

  def self.select_raw(select)
    JSON.parse %x[ cat $MUSIC_DB | jq '[.[] | #{select}]' ]
  end

  @meta_to_db = {"artist"=>"artist", "title"=>"name", "album"=>"playlist", "genre" => "tags"}

  def self.metadata(item)
    metadata = JSON.parse(%x[ ffprobe -v quiet -print_format json -show_format "$MUSIC_DIR/#{item["id"]}.m4a"])
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

  def self.tag(items, workers: 1, log_dir: nil)
    return tag_parallel(items, workers, log_dir: log_dir) if workers > 1

    items.each do |i|
      tag_single(i)
    end
  end

  def self.tag_single(i)
    file_tags = self.parse_tags i
    item = i.select {|k,_| @meta_to_db.values.include? k}
    puts "file_tags: #{file_tags}" if $options[:verbose]
    puts "item: #{item}" if $options[:verbose]
    diff = hash_diff item, file_tags
    if diff.empty?
      return :skipped
    else
      meta_str = diff.keys
        .map {|k| [" -metadata ", @meta_to_db.invert[k], "=", "#{item[k].to_s.shellescape}", " "]}
        .join ""
      if $options[:dry_run]
        puts meta_str
        return :dry_run
      else
        puts meta_str if $options[:verbose]
        file = i["id"]+".m4a"
        tmp = i["id"]+".tmp.m4a"
        log = i["id"]+".log.m4a"
        system("ffmpeg -v warning -i $MUSIC_DIR/#{file} #{meta_str} $MUSIC_DIR/#{tmp} 2>&1 | tee -a $MUSIC_DIR/#{log} && mv $MUSIC_DIR/#{tmp} $MUSIC_DIR/#{file}")
        return :tagged
      end
    end
  end

  def self.tag_parallel(items, workers, log_dir: nil)
    require 'thread'
    require 'fileutils'

    # Setup logging
    if log_dir
      FileUtils.mkdir_p(log_dir)
      timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
      log_file = File.join(log_dir, "music-import-#{timestamp}.log")
      failures_file = File.join(log_dir, "music-import-#{timestamp}.failures")
      log = File.open(log_file, "a")
      failures = File.open(failures_file, "a")
      log.puts "Starting tag_parallel at #{Time.now} with #{workers} workers for #{items.size} items"
    end

    queue = Queue.new
    items.each { |i| queue << i }
    workers.times { queue << :done }

    total = items.size
    completed = 0
    failed_count = 0
    mutex = Mutex.new

    threads = workers.times.map do
      Thread.new do
        while (item = queue.pop) != :done
          result, error = tag_single_with_error(item)
          mutex.synchronize do
            completed += 1
            print "\r[#{completed}/#{total}] #{item["id"]} - #{result}    "
            if log_dir
              log.puts "[#{Time.now}] #{item["id"]} - #{result}"
              if result == :failed
                failed_count += 1
                failures.puts "#{item["id"]} | #{item["artist"]} - #{item["name"]}"
                failures.puts "  Error: #{error}"
                failures.puts ""
              end
              log.flush
              failures.flush
            end
          end
        end
      end
    end

    threads.each(&:join)

    if log_dir
      log.puts "Finished at #{Time.now}: #{total - failed_count} succeeded, #{failed_count} failed"
      log.close
      failures.close
      puts "\nDone tagging #{total} files with #{workers} workers (#{failed_count} failures)"
      puts "Log: #{log_file}"
      puts "Failures: #{failures_file}" if failed_count > 0
    else
      puts "\nDone tagging #{total} files with #{workers} workers"
    end
  end

  def self.tag_single_with_error(i)
    file_tags = self.parse_tags i
    item = i.select {|k,_| @meta_to_db.values.include? k}
    puts "file_tags: #{file_tags}" if $options[:verbose]
    puts "item: #{item}" if $options[:verbose]
    diff = hash_diff item, file_tags
    if diff.empty?
      return [:skipped, nil]
    else
      meta_str = diff.keys
        .map {|k| [" -metadata ", @meta_to_db.invert[k], "=", "#{item[k].to_s.shellescape}", " "]}
        .join ""
      if $options[:dry_run]
        puts meta_str
        return [:dry_run, nil]
      else
        puts meta_str if $options[:verbose]
        file = i["id"]+".m4a"
        tmp = i["id"]+".tmp.m4a"
        output = `ffmpeg -v warning -i "$MUSIC_DIR/#{file}" #{meta_str} "$MUSIC_DIR/#{tmp}" 2>&1`
        if $?.success? && File.exist?("#{ENV['MUSIC_DIR']}/#{tmp}")
          system("mv \"$MUSIC_DIR/#{tmp}\" \"$MUSIC_DIR/#{file}\"")
          return [:tagged, nil]
        else
          # Cleanup tmp file if it exists
          system("rm -f \"$MUSIC_DIR/#{tmp}\"")
          return [:failed, output.strip]
        end
      end
    end
  end

end
