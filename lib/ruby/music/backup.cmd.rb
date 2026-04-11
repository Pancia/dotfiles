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

      section = ->(title) { puts "", "── #{title} " + "─" * [60 - title.length, 2].max }
      run = ->(env, cmd) {
        puts "$ #{cmd}"
        return if $options[:dry_run]
        ok = env ? system(env, cmd) : system(cmd)
        puts "  ✗ exit #{$?.exitstatus}" unless ok
        ok
      }

      # 1. rsync MUSIC_LIBRARY/ -> MUSIC_CLOUD (trailing slash = contents)
      section.call("rsync  library → cloud")
      rsync_flags = %w[-a --info=stats1,progress2 --no-inc-recursive
                       --exclude .DS_Store --exclude .Spotlight-V100]
      rsync_flags << "--delete" if $options[:delete]
      src = lib.chomp("/") + "/"
      run.call(nil, ["rsync", *rsync_flags, src, cloud].shelljoin)

      # 2. restic snapshots
      pw_cmd = "security find-generic-password -a restic -s music-backup -w"
      restic_repos = [
        ["ProtonDrive", ENV['MUSIC_BACKUPS']],
        ["USB",         "/Volumes/vansuny128/backups/music"],
      ]
      restic_repos.each do |label, repo|
        next unless repo
        section.call("restic  #{label}  (#{repo})")

        # Skip USB if volume not mounted
        if label == "USB" && !File.directory?("/Volumes/vansuny128")
          puts "  ⊘ volume not mounted, skipping"
          next
        end

        env = { "RESTIC_PASSWORD_COMMAND" => pw_cmd, "RESTIC_REPOSITORY" => repo }

        # Auto-init repo if missing (config file is the reliable marker)
        unless File.exist?(File.join(repo, "config"))
          puts "  ⚠ repo not initialized, running `restic init`"
          unless run.call(env, "restic init")
            puts "  ✗ init failed, skipping #{label}"
            next
          end
        end

        run.call(env, "restic backup #{lib.shellescape}")
      end
    }
  end
end
