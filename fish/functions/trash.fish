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

function _record_trash --description 'Record trashed file (fname, encoded_dir, timestamp, dest, id)'
    set -l history_file (_trash_history_path)
    set -l max_history 500

    if not test -d (dirname "$history_file")
        mkdir -p (dirname "$history_file")
    end
    printf '%s\t%s\t%s\t%s\t%s\n' "$argv[1]" "$argv[2]" "$argv[3]" "$argv[4]" "$argv[5]" >> "$history_file"
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

function _trash_entry_id --description 'Resolve the stable id for a history entry (dest, stored_id)'
    # Prefer the id stored at trash time; fall back to a hash of the trash
    # destination for legacy entries recorded before ids existed.
    if test -n "$argv[2]"
        echo "$argv[2]"
    else
        printf '%s' "$argv[1]" | shasum -a 256 | string sub -l 8
    end
end

function _trash_put --description 'Move files to trash with history'
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
            # Avoid silently clobbering a file trashed earlier this second with
            # the same name and cwd (timestamp is second-granularity).
            if test -e "$dest"
                set raw_name "$raw_name-"(exocortex-id)
                set dest "$trash_dir/"(_trash_safe_name "$raw_name")
            end
            set -l id (exocortex-id)
            echo "[dotfiles/trash] INFO: moving '$f' to '$dest'"
            mv "$f" "$dest"
            or begin
                echo "[dotfiles/trash] ERROR: failed to move '$f'" >&2
                set failed true
                continue
            end
            _record_trash "$f" "$prefix" "$suffix" "$dest" "$id"
        else
            set failed true
            echo "[dotfiles/trash] ERROR: file not found: '$f'" >&2
        end
    end

    if test "$failed" = "true"
        return 1
    end
end

function _trash_list --description 'List trashed files (human table, or --json)'
    argparse j/json -- $argv
    or return 1

    set -l history_file (_trash_history_path)

    if not test -s "$history_file"
        if set -q _flag_json
            echo '[]'
        end
        return 0
    end

    # Newest first
    set -l lines (tail -r "$history_file")

    if set -q _flag_json
        set -l objects
        for line in $lines
            set -l parts (string split \t -- "$line")
            set -l fname $parts[1]
            set -l folder (_trash_decode_path "$parts[2]")
            set -l id (_trash_entry_id "$parts[4]" "$parts[5]")
            set -l orig "$folder/$fname"
            if string match -q '/*' "$fname"
                set orig "$fname"
            end
            set -l present 0
            if test -e "$parts[4]"
                set present 1
            end
            set -a objects (jq -c -n \
                --arg id "$id" \
                --arg path "$orig" \
                --arg dir "$folder" \
                --arg when "$parts[3]" \
                --arg dest "$parts[4]" \
                --arg p "$present" \
                '{id:$id, path:$path, dir:$dir, when:$when, dest:$dest, present:($p=="1")}')
        end
        printf '%s\n' $objects | jq -s '.'
    else
        printf '%-12s  %-19s  %-7s  %s\n' ID WHEN PRESENT ORIGINAL
        for line in $lines
            set -l parts (string split \t -- "$line")
            set -l fname $parts[1]
            set -l folder (_trash_decode_path "$parts[2]")
            set -l id (_trash_entry_id "$parts[4]" "$parts[5]")
            set -l orig "$folder/$fname"
            if string match -q '/*' "$fname"
                set orig "$fname"
            end
            set -l present no
            if test -e "$parts[4]"
                set present yes
            end
            printf '%-12s  %-19s  %-7s  %s\n' "$id" "$parts[3]" "$present" "$orig"
        end
    end
end

function _trash_restore_line --description 'Restore the entry at the given history line number'
    set -l history_file (_trash_history_path)
    set -l line_num $argv[1]

    set -l line (awk "{ if (NR == $line_num) { print \$0 } }" $history_file)
    if test -z "$line"
        echo "[ERROR][restore]: line $line_num not found in history" >&2
        return 1
    end

    # Fields: fname, encoded_dir, timestamp, trash_path, id
    set -l parts (string split \t -- "$line")
    set -l fname $parts[1]
    set -l folder (_trash_decode_path "$parts[2]")
    set -l src $parts[4]

    set -l dest "$folder/$fname"
    if string match -q '/*' "$fname"
        set dest "$fname"
    end

    if not test -e "$src"
        echo "[ERROR][restore]: file not found in trash: $src" >&2
        echo "  (volume may be unmounted)" >&2
        return 1
    end

    # Don't overwrite a live file that has reappeared at the original path.
    if test -e "$dest"
        echo "[ERROR][restore]: '$dest' already exists; refusing to overwrite" >&2
        return 1
    end

    echo "[dotfiles/restore] INFO: moving $src -> $dest"
    mkdir -p (dirname "$dest")

    command mv "$src" "$dest"
    and sed -i '' "$line_num"d $history_file
end

function _trash_restore --description 'Restore a file from trash (--last, <id>, or interactive)'
    argparse last -- $argv
    or return 1

    set -l history_file (_trash_history_path)
    set -l line_num

    if set -q _flag_last
        if not test -s "$history_file"
            echo "[ERROR][restore]: trash history is empty" >&2
            return 1
        end
        set line_num (wc -l < "$history_file" | string trim)
    else if test (count $argv) -ge 1
        # Restore by stable id (newest match wins on the unlikely collision)
        if not test -s "$history_file"
            echo "[ERROR][restore]: trash history is empty" >&2
            return 1
        end
        set -l want $argv[1]
        set -l n 0
        set -l match
        for line in (cat "$history_file")
            set n (math $n + 1)
            set -l parts (string split \t -- "$line")
            if test (_trash_entry_id "$parts[4]" "$parts[5]") = "$want"
                set match $n
            end
        end
        if test -z "$match"
            echo "[ERROR][restore]: no trash entry with id '$want' (run \`trash list\`)" >&2
            return 1
        end
        set line_num $match
    else if isatty stdin
        # Interactive picker for humans
        set -l selected (mktemp)
        cat -n $history_file | tail -r | peco --on-cancel error >$selected
        set -l peco_status $status
        set line_num (cat "$selected" | string trim | cut -f1)
        command rm -f "$selected"

        if test $peco_status -ne 0; or test -z "$line_num"
            return 1
        end
    else
        echo "[ERROR][restore]: specify --last or an <id> (see \`trash list\`)" >&2
        return 1
    end

    _trash_restore_line $line_num
end

function _trash_usage --description 'Show trash/restore usage'
    printf '%s\n' \
        "trash — move files to the trash, with restore support" \
        "" \
        "Usage:" \
        "  trash <path>...        Move files to the trash (same as 'trash put')" \
        "  trash put <path>...    Move files to the trash" \
        "  trash list [--json]    List trashed files, newest first" \
        "  trash restore --last   Restore the most recently trashed file" \
        "  trash restore <id>     Restore the entry with the given id (see 'trash list')" \
        "  trash restore          Interactive picker (peco; tty only)" \
        "  trash help             Show this help" \
        "" \
        "Notes:" \
        "  Reserved first words: put, list, restore, help, -h, --help." \
        "  To trash a file literally named one of these, use 'trash put <name>'." \
        "  'trash list' shows the most recent 500 entries; older ones age out."
end

function trash --description 'Move files to trash, or manage trashed files'
    switch "$argv[1]"
        case put
            _trash_put $argv[2..-1]
        case list
            _trash_list $argv[2..-1]
        case restore
            _trash_restore $argv[2..-1]
        case help -h --help
            _trash_usage
        case ''
            _trash_usage
        case '*'
            _trash_put $argv
    end
end

function restore --description 'Restore files from trash'
    trash restore $argv
end

function rm --description 'rm with warning to use trash' --wraps rm
    if isatty stdin
        echo "[rm] WARNING: prefer \`trash\`" >&2
    end
    command rm $argv
end
