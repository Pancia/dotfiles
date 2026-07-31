function __cc_resume_id --description 'Session id from a --resume/-r argv, empty if there is none'
    # Pure-fish argv scan, no subprocess: this runs on EVERY claude launch,
    # before anything knows whether isolation applies at all.
    #
    # A bare -c/--continue carries no session id, so its slot cannot be looked
    # up and that session runs un-isolated. The wrapper says so out loud —
    # a documented limitation rather than a silent one.
    set -l want 0
    for arg in $argv
        if test $want -eq 1
            # `--resume` with no id opens the picker, so the next token is
            # another flag rather than a session id.
            if string match -q -- '-*' $arg
                set want 0
            else
                printf '%s\n' $arg
                return 0
            end
        end
        switch $arg
            case --resume -r
                set want 1
            case '--resume=*'
                printf '%s\n' (string replace -- '--resume=' '' $arg)
                return 0
        end
    end
    return 1
end
