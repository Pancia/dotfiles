function fancy_ctrl_z
    set -l cmd (commandline)
    if test -z "$cmd"
        set -l job_count (jobs | wc -l | string trim)
        if test $job_count -ge 1
            jobs
            commandline -i "fg %"
        end
        commandline -f repaint
    end
end
