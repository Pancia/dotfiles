if test -f ~/dotfiles/vendor/MANIFEST.json
    set -l cache_dir ~/.cache/dotfiles
    test -d $cache_dir; or mkdir -p $cache_dir
    set -l last_check_file $cache_dir/vendor-last-check
    set -l now (date +%s)
    set -l threshold 604800
    set -l should_check 0
    if not test -f $last_check_file
        set should_check 1
    else if test (math $now - (cat $last_check_file)) -gt $threshold
        set should_check 1
    end
    if test $should_check -eq 1
        echo $now > $last_check_file
        ~/dotfiles/bin/vendor check --quiet &
    end
end
