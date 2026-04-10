# Trash management system
function _trash_history_path
    echo "$HOME/.cache/dotfiles/trash/history"
end

function _trash_encode_path --description 'URL-encode a path for use in trash filenames'
    string escape --style=url "$argv[1]" | string replace -a '/' '%2F'
end

function _trash_decode_path --description 'Decode a URL-encoded trash path'
    string replace -a '%2F' '/' "$argv[1]" | string unescape --style=url
end

function _trash_safe_name --description 'Truncate trash filename to fit macOS 255-byte limit'
    set -l name "$argv[1]"
    set -l byte_len (printf '%s' "$name" | wc -c | string trim)
    if test $byte_len -le 255
        echo "$name"
        return
    end
    # Generate a compact unique ID, truncate name to fit
    set -l uid (exocortex-id)
    set -l uid_len (math (string length "$uid") + 1)
    set -l max_bytes (math 255 - $uid_len)
    set -l truncated "$name"
    while test (printf '%s' "$truncated" | wc -c | string trim) -gt $max_bytes
        set truncated (string sub -l (math (string length "$truncated") - 1) "$truncated")
    end
    echo "$truncated-$uid"
end

function _record_trash --description 'Record trashed file'
    set -l history_file (_trash_history_path)
    set -l max_history 500

    if not test -d (dirname "$history_file")
        mkdir -p (dirname "$history_file")
    end
    printf '%s\t%s\t%s\t%s\n' "$argv[1]" "$argv[2]" "$argv[3]" "$argv[4]" >> "$history_file"
    if test -f "$history_file"; and test (wc -l < "$history_file") -gt $max_history
        set -l tmp (mktemp)
        awk -F'\t' '{if (NR != 1) { print $0 } }' "$history_file" > "$tmp"
        mv "$tmp" "$history_file"
    end
end

function _trash_dir_for_path --description 'Return the trash directory for a file path'
    # Resolve only the directory to avoid following a final symlink component
    set -l resolved_dir (realpath (dirname "$argv[1]"))
    set -l file_path "$resolved_dir/"(basename "$argv[1]")
    if string match -q '/Volumes/*' "$file_path"
        set -l volume (string replace -r '^(/Volumes/[^/]+).*' '$1' "$file_path")
        set -l trash_dir "$volume/.Trashes/"(id -u)
        if not test -d "$trash_dir"
            mkdir -p "$trash_dir" 2>/dev/null
            or begin
                echo "[dotfiles/trash] WARN: can't create $trash_dir, using ~/.Trash" >&2
                echo "$HOME/.Trash"
                return
            end
        end
        echo "$trash_dir"
    else
        echo "$HOME/.Trash"
    end
end

function trash --description 'Move files to trash with history'
    set -l dir (pwd)
    set -l timestamp (date '+%Y-%m-%d_%X')
    set -l prefix (_trash_encode_path "$dir")
    set -l suffix "$timestamp"
    set -l failed false

    for f in $argv
        if test -e "$f"
            set -l trash_dir (_trash_dir_for_path "$f")
            set -l f_encoded (_trash_encode_path "$f")
            set -l raw_name "$prefix>>>$f_encoded<<<$suffix"
            set -l dest "$trash_dir/"(_trash_safe_name "$raw_name")
            echo "[dotfiles/trash] INFO: moving '$f' to '$dest'"
            mv "$f" "$dest"
            or begin
                echo "[dotfiles/trash] ERROR: failed to move '$f'" >&2
                set failed true
                continue
            end
            _record_trash "$f" "$prefix" "$suffix" "$dest"
        else
            set failed true
            echo "[dotfiles/trash] ERROR: file not found: '$f'" >&2
        end
    end

    if test "$failed" = "true"
        return 1
    end
end

function restore --description 'Restore files from trash'
    set -l history_file (_trash_history_path)

    set -l line_num
    if test (count $argv) -eq 0
        set -l selected (mktemp)
        cat -n $history_file | tail -r | peco --on-cancel error > $selected
        set -l peco_status $status
        set line_num (cat "$selected" | string trim | cut -f1)
        command rm -f "$selected"

        if test $peco_status -ne 0; or test -z "$line_num"
            return 1
        end
    else
        set line_num $argv[1]
    end

    set -l line (awk "{ if (NR == $line_num) { print \$0 } }" $history_file)
    if test -z "$line"
        echo "[ERROR][restore]: Line $line_num not found in history" >&2
        return 1
    end

    # Read fields directly from history: fname, encoded_dir, timestamp, trash_path
    set -l fname (echo "$line" | cut -f1)
    set -l folder (_trash_decode_path (echo "$line" | cut -f2))
    set -l src (echo "$line" | cut -f4)

    # Construct destination path
    set -l dest
    if string match -q '/*' "$fname"
        set dest "$fname"
    else
        set dest "$folder/$fname"
    end

    if not test -e "$src"
        echo "[ERROR][restore]: file not found in trash: $src" >&2
        echo "  (volume may be unmounted)" >&2
        return 1
    end

    echo "[dotfiles/restore] INFO: moving $src -> $dest"
    mkdir -p (dirname "$dest")

    command mv "$src" "$dest"
    and sed -i '' "$line_num"d $history_file
end

function rm --description 'rm with warning to use trash' --wraps rm
    if isatty stdin
        echo "[rm] WARNING: prefer \`trash\`" >&2
    end
    command rm $argv
end
