function fisher-up --description 'fisher update + restore locally-patched plugin files'
    set -l dotfiles (realpath ~/dotfiles)

    if not test -d $dotfiles/.jj
        echo "fisher-up: $dotfiles is not a jj repo" >&2
        return 1
    end

    set -l baseline master
    set -l tracked (jj --repository $dotfiles file list -r $baseline fish/functions 2>/dev/null)

    if test (count $tracked) -eq 0
        echo "fisher-up: warning — no tracked files under fish/functions/ in $baseline" >&2
        echo "fisher-up: patches must be committed to $baseline for restore to work" >&2
    end

    if not functions -q _fisher_orig
        echo "fisher-up: _fisher_orig not found — was conf.d/fisher-wrap.fish sourced?" >&2
        return 1
    end

    _fisher_orig update $argv
    or return $status

    set -l to_restore
    for f in $tracked
        if not jj --repository $dotfiles file show -r $baseline -- $f 2>/dev/null | cmp -s - $dotfiles/$f
            set -a to_restore $f
        end
    end

    if test (count $to_restore) -eq 0
        echo "fisher-up: no tracked files clobbered"
        return 0
    end

    echo "fisher-up: restoring tracked files clobbered by fisher:"
    printf '  %s\n' $to_restore
    jj --repository $dotfiles restore --from $baseline -- $to_restore
end
