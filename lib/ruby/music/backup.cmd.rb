module MusicCMD
  def backup(opts)
    opts.banner = "Usage: backup [--delete]"
    opts.info = "Backup music library to ProtonDrive and restic"
    opts.separator "    Rsyncs $MUSIC_LIBRARY -> $MUSIC_CLOUD, then snapshots to restic."
    opts.separator "    Safe to run frequently — rsync and restic are incremental."
    opts.separator ""
    opts.separator "    --delete    Remove files from cloud that no longer exist in library."
    opts.separator "                Only use manually — post-commit hook never passes this."
    opts.on("--delete", "Propagate deletions to cloud") { $options[:delete] = true }
    lambda { |*args|
      lib = ENV['MUSIC_LIBRARY']
      cloud = ENV['MUSIC_CLOUD']
      abort "MUSIC_LIBRARY not set" unless lib
      abort "MUSIC_CLOUD not set" unless cloud

      # 1. rsync MUSIC_LIBRARY/ -> MUSIC_CLOUD (trailing slash = contents)
      rsync_flags = %w[-a --progress --exclude .DS_Store --exclude .Spotlight-V100]
      rsync_flags << "--delete" if $options[:delete]
      src = lib.chomp("/") + "/"
      cmd = ["rsync", *rsync_flags, src, cloud].shelljoin
      puts cmd if $options[:verbose]
      system(cmd) unless $options[:dry_run]

      # 2. restic snapshots
      pw_cmd = "security find-generic-password -a restic -s music-backup -w"
      restic_repos = [
        ["ProtonDrive", ENV['MUSIC_BACKUPS']],
        ["USB",         "/Volumes/vansuny128/backups/music"],
      ]
      restic_repos.each do |label, repo|
        next unless repo
        if label == "USB" && !File.directory?(File.dirname(repo))
          puts "Skipping #{label} restic — volume not mounted" if $options[:verbose]
          next
        end
        env = { "RESTIC_PASSWORD_COMMAND" => pw_cmd, "RESTIC_REPOSITORY" => repo }
        restic_cmd = "restic backup #{lib.shellescape}"
        puts "[#{label}] #{restic_cmd}" if $options[:verbose]
        system(env, restic_cmd) unless $options[:dry_run]
      end
    }
  end
end
