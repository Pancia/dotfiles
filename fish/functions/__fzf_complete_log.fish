function __fzf_complete_log
    set -q _FZF_COMPLETE_DEBUG; or return
    set -l t (perl -MTime::HiRes -e 'printf "%.4f", Time::HiRes::time')
    echo "[$t] $argv" >> /tmp/fzf_complete.log
end
