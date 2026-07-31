function __cc_resume_requested --description 'True if argv asks to resume or continue a session'
    # Separate from __cc_resume_id because `-c` / `--continue` carry NO session
    # id: there is nothing to look a slot up by, so the answer to "which slot"
    # is "none", which is indistinguishable from "not a resume at all" unless
    # this is asked separately. Conflating them made a bare `-c` claim a fresh
    # slot and silently continue whatever conversation last ran there.
    for a in $argv
        switch $a
            case -r --resume '--resume=*' -c --continue '--continue=*'
                return 0
        end
    end
    return 1
end
