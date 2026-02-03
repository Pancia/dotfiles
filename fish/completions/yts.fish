# Completions for yts (v1.2.0)

complete -c yts -f

# Helper function to list job IDs with descriptions
function __yts_list_jobs
    set -l jobs_dir ~/.local/state/youtube-transcribe/jobs
    set -l logs_dir ~/.local/state/youtube-transcribe/logs

    # List log files sorted by modification time (newest first)
    for log_file in (ls -t $logs_dir/*.log 2>/dev/null)
        set -l job_id (basename $log_file .log)
        set -l json_file $jobs_dir/$job_id.json

        # Try to get metadata from JSON
        if test -f "$json_file"
            set -l title (jq -r '.title // "Unknown"' $json_file 2>/dev/null | string sub -l 40)
            set -l state (jq -r '.state // "unknown"' $json_file 2>/dev/null)
            printf '%s\t%s (%s)\n' $job_id $title $state
        else
            # Fallback to just job ID
            printf '%s\n' $job_id
        end
    end
end

# Options
complete -c yts -s s -l sections -d 'Time ranges (e.g., 40:00-45:35,1:20:00-1:25:00)'
complete -c yts -s c -l context -d 'Additional context for summary prompt'
complete -c yts -s t -l transcribe -d 'Transcribe only (no summary)'
complete -c yts -s H -l health -d 'Check service health'
complete -c yts -s S -l status -rka '(__yts_list_jobs)' -d 'Get status of a job'
complete -c yts -s L -l logs -rka '(__yts_list_jobs)' -d 'Get logs for a job'
complete -c yts -s T -l tail -d 'Number of log lines to return'
complete -c yts -s i -l info -d 'Show API info'
complete -c yts -s k -l kill -rka '(__yts_list_jobs)' -d 'Kill a specific job'
complete -c yts -s K -l kill-all -d 'Kill all active jobs'
complete -c yts -s Z -l service-log -d 'View service log (less +GF)'
complete -c yts -s h -l help -d 'Show help'

# History subcommand
complete -c yts -n '__fish_use_subcommand' -a history -d 'Show job history'
complete -c yts -n '__fish_seen_subcommand_from history' -s j -l json -d 'Output as JSON'
complete -c yts -n '__fish_seen_subcommand_from history' -s l -l limit -d 'Number of entries (default: 20)'
complete -c yts -n '__fish_seen_subcommand_from history' -s a -l all -d 'Show all history'
complete -c yts -n '__fish_seen_subcommand_from history' -s s -l state -rka 'complete error interrupted' -d 'Filter by state'
