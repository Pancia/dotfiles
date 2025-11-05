# Trash management system
set -gx TRASH_CACHE_MAX_HISTORY 500
set -gx TRASH_CACHE_HISTORY "$HOME/.cache/dotfiles/trash/history"

function _record_trash --description 'Record trashed file'
    if not test -d (dirname "$TRASH_CACHE_HISTORY")
        mkdir -p (dirname "$TRASH_CACHE_HISTORY")
    end
    printf '%s\t%s\t%s\t%s\n' "$argv[1]" "$argv[2]" "$argv[3]" "$argv[4]" >> "$TRASH_CACHE_HISTORY"
    if test (wc -l < "$TRASH_CACHE_HISTORY") -gt $TRASH_CACHE_MAX_HISTORY
        set -l tmp (mktemp)
        awk -F'\t' '{if (NR != 1) { print $0 } }' "$TRASH_CACHE_HISTORY" > "$tmp"
        mv "$tmp" "$TRASH_CACHE_HISTORY"
    end
end

function trash --description 'Move files to trash with history'
    set -l dir (pwd)
    set -l timestamp (date '+%Y-%m-%d_%X')
    set -l prefix (string replace -a '/' '%' "$dir")
    set -l suffix "$timestamp"
    set -l failed false

    for f in $argv
        if test -e "$f"
            set -l f_encoded (string replace -a '/' '%' "$f")
            set -l dest "$HOME/.Trash/$prefix>>>$f_encoded<<<$suffix"
            echo "[dotfiles/trash] INFO: moving '$f' to '$dest'"
            mv "$f" "$dest"
            _record_trash "$f" "$prefix" "$suffix" "$dest"
        else
            set failed true
            echo "[dotfiles/trash] ERROR: file not found: '$f'" >&2
        end
    end

    test "$failed" = "true"; and return 1
end

function restore --description 'Restore files from trash'
    if test (count $argv) -eq 0
        set -l selected (mktemp)
        cat -n $TRASH_CACHE_HISTORY | tail -r | peco --on-cancel error > $selected
        and restore $selected
    else
        set -l line_num (cat $argv[1] | cut -f1)
        if test -z "$line_num"
            echo "[ERROR][restore]: Must select a line" >&2
            return 1
        end

        set -l line (awk "{ if (NR == $line_num) { print \$0 } }" $TRASH_CACHE_HISTORY)
        set -l src (echo "$line" | cut -f4)

        # Extract the filename from the trash path
        set -l trash_basename (basename "$src")

        # Parse the encoded filename: prefix>>>filename<<<timestamp
        set -l prefix_encoded (echo "$trash_basename" | sed 's/>>>.*//')
        set -l fname_encoded (echo "$trash_basename" | sed 's/.*>>>//; s/<<<.*//')

        # Decode the prefix (folder) and filename
        set -l folder (string replace -a '%' '/' "$prefix_encoded")
        set -l fname (string replace -a '%' '/' "$fname_encoded")

        # Construct destination path
        if string match -q '/*' "$fname"
            set -l dest "$fname"
        else
            set -l dest "$folder/$fname"
        end

        echo "[dotfiles/restore] INFO: moving $src -> $dest"

        # Create destination directory if it doesn't exist
        mkdir -p (dirname "$dest")

        mv "$src" "$dest"
        and sed -i '' "$line_num"d $TRASH_CACHE_HISTORY
    end
end

function rm --description 'rm with warning to use trash' --wraps rm
    if isatty stdout
        echo "[rm] WARNING: prefer \`trash\`" >&2
    end
    command rm $argv
end
