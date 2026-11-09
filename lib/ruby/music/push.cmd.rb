require "json"
require "set"
require "shellwords"
require "tempfile"
require "tmpdir"

module MusicCMD
  PUSH_HOST = "anthony@anthonydambrosio.me"
  PUSH_REMOTE = "music-server:/mnt/MyMusic/my-music"
  PUSH_TRACKS = "/mnt/MyMusic/my-music/"
  PUSH_PLAYLISTS = "/mnt/MyMusic/playlists/"
  PUSH_MOUNTED = "mount | grep -q '^/dev/sd2a on /mnt '"
  # A track is tagged after it is copied. --ignore-existing never updates a file,
  # so sending one mid-import would freeze its missing tags on the server.
  PUSH_MIN_AGE = 120
  # Every wait is bounded, because the commit hook runs this unattended and a hung
  # push would block all later ones.
  PUSH_RSYNC_BOUNDS = ["--timeout=60", "-e",
                       "ssh -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=3"]

  def push(opts)
    opts.banner = "Usage: push [-n]"
    opts.info = "Send new tracks and playlists from $MUSIC_CLOUD to the Vultr server"
    opts.separator "    Sends each catalog track the server lacks, then updates its playlists."
    opts.separator "    Only adds tracks: never deletes or overwrites one on the server."
    opts.separator "    Run it again to pick up tracks that were still being imported."
    lambda { |*_args|
      ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", PUSH_HOST]
      unless system(*ssh, PUSH_MOUNTED)
        abort "push: the server is unreachable or its disk is locked. Run bin/mnt there."
      end

      cloud = ENV.fetch("MUSIC_CLOUD").chomp("/") + "/"
      catalog = JSON.parse(File.read(ENV.fetch("MUSIC_CATALOG")))
      listing = %x[rclone lsf #{PUSH_REMOTE.shellescape} --files-only --log-level ERROR]
      abort "push: could not list the server's tracks" unless $?.success?
      on_server = listing.split("\n").to_set

      now = Time.now
      send, recent, absent = [], [], []
      catalog.each_key do |id|
        name = "#{id}.m4a"
        next if on_server.include?(name)
        path = cloud + name
        if !File.size?(path) then absent << name
        elsif now - File.mtime(path) < PUSH_MIN_AGE then recent << name
        else send << name
        end
      end

      puts "To send: #{send.size}. Too recent, skipped: #{recent.size}. " \
           "In the catalog with no usable file: #{absent.size}."
      absent.first(10).each { |name| puts "  no file: #{name}" }
      if $options[:dry_run]
        send.first(20).each { |name| puts "  would send: #{name}" }
        next
      end

      unless send.empty?
        Tempfile.create("music-push") do |list|
          list.puts(send)
          list.flush
          # No --partial: it keeps a cut-off file under its final name, and a later
          # push would treat that track as already sent.
          ok = system("rsync", "-rtp", "--chmod=F640,D750", "--ignore-existing",
                      "--min-size=1", "--files-from=#{list.path}", *PUSH_RSYNC_BOUNDS,
                      cloud, "#{PUSH_HOST}:#{PUSH_TRACKS}")
          abort "push: track upload failed. Nothing was deleted; run it again." unless ok
        end
      end

      available = on_server + send
      Dir.mktmpdir("music-push") do |dir|
        count = _push_write_playlists(catalog, available, dir)
        # -c, not -t: only a changed playlist is rewritten, which is what makes
        # Navidrome's next scan re-import it.
        ok = system("rsync", "-rcp", "--chmod=F640,D750", *PUSH_RSYNC_BOUNDS, "#{dir}/",
                    "#{PUSH_HOST}:#{PUSH_PLAYLISTS}")
        abort "push: playlist upload failed" unless ok
        puts "Sent #{send.size} track(s), checked #{count} playlist(s)."
      end
      puts "Navidrome finds them at its next hourly scan."
      puts "For cmus, run: service restart music-mount (this stops playback briefly)."
    }
  end

  # Keep names in step with what is already on the server: a different name
  # would leave a duplicate playlist there.
  def _push_write_playlists(catalog, available, dir)
    lists = catalog.values.group_by { |track| track["playlist"] }
    used = Set.new
    lists.sort_by { |name, _| name.to_s }.each do |name, tracks|
      stem = name.to_s.gsub(/[\/\\:\x00-\x1f]/, "-").gsub(/\A[. ]+|[. ]+\z/, "")
      stem = "unnamed" if stem.empty?
      stem += "_" while used.include?(stem.downcase)
      used << stem.downcase
      lines = ["#EXTM3U", "#PLAYLIST:#{name}"]
      tracks.sort_by { |t| [t["artist"].to_s, t["name"].to_s] }.each do |t|
        next unless available.include?("#{t["id"]}.m4a")
        lines << "#EXTINF:-1,#{t["artist"]} - #{t["name"]}"
        lines << "../my-music/#{t["id"]}.m4a"
      end
      File.write(File.join(dir, stem[0, 200] + ".m3u"), lines.join("\n") + "\n")
    end
    lists.size
  end
end
