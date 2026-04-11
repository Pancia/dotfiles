function ccpu --description 'Launch claude wrapper running /cc:pending-updates'
    set -l prompt /cc:pending-updates
    if test -d .jj
        set prompt "$prompt (this is a jj repo)"
    else if test -d .git; or git rev-parse --git-dir >/dev/null 2>&1
        set prompt "$prompt (this is a git repo)"
    end
    my-claude-code-wrapper $prompt $argv
end
