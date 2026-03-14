function _ccs_file
    echo (pwd)"/.claude-sessions"
end

function _ccs_add --description 'Add a claude session'
    set -l input (string join ' ' $argv)

    # Extract ID from either raw id or 'claude --resume <id>' format
    set -l id (string replace -r '.*--resume\s+' '' -- "$input" | string split ' ')[1]
    if test -z "$id"
        echo "Usage: ccs add <id> [title]"
        echo "       ccs add claude --resume <id> [title]"
        return 1
    end

    # Everything after the id is the title
    set -l title
    set -l found_id 0
    for arg in $argv
        if test $found_id -eq 1
            set -a title $arg
        else if test "$arg" = "$id"
            set found_id 1
        end
    end
    set title (string join ' ' $title)

    set -l timestamp (date '+%Y-%m-%d %H:%M')

    # Append to file, dedup by id
    set -l file (_ccs_file)
    if test -f "$file"
        # Remove existing entry with same id
        string match -v -r "^$id\t" < "$file" > "$file.tmp"
        mv "$file.tmp" "$file"
    end
    if test -n "$title"
        printf '%s\t%s\t%s\n' "$id" "$timestamp" "$title" >> "$file"
        echo "Added session: $id ($timestamp — $title)"
    else
        printf '%s\t%s\n' "$id" "$timestamp" >> "$file"
        echo "Added session: $id ($timestamp)"
    end
end

function _ccs_list --description 'List claude sessions'
    set -l file (_ccs_file)
    if not test -f "$file"
        return 1
    end
    set -l lines (cat "$file" 2>/dev/null)
    if test -z "$lines"
        return 1
    end
    for line in $lines
        set -l parts (string split \t "$line")
        set -l id $parts[1]
        set -l timestamp $parts[2]
        set -l title $parts[3]
        set -l meta
        if test -n "$timestamp" -a -n "$title"
            set meta "$timestamp — $title"
        else if test -n "$timestamp"
            set meta "$timestamp"
        end
        if test -n "$meta"
            printf '  %s  %s\n' (set_color cyan)"$id"(set_color normal) (set_color brblack)"$meta"(set_color normal)
        else
            printf '  %s\n' (set_color cyan)"$id"(set_color normal)
        end
    end
end

function _ccs_remove --description 'Remove a claude session'
    set -l id $argv[1]
    if test -z "$id"
        echo "Usage: ccs rm <id>"
        return 1
    end
    set -l file (_ccs_file)
    if not test -f "$file"
        echo "No .claude-sessions file"
        return 1
    end
    string match -v -r "^$id" < "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
    echo "Removed session $id"
end

function _ccs_open --description 'Pick and resume a session'
    set -l file (_ccs_file)
    if not test -f "$file"
        echo "No .claude-sessions file"
        return 1
    end
    set -l lines (cat "$file" 2>/dev/null)
    if test -z "$lines"
        echo "No sessions"
        return 1
    end

    set -l choice (printf '%s\n' $lines | fzf --prompt="Claude session> " --no-sort)
    if test -n "$choice"
        set -l id (string split \t "$choice")[1]
        echo "Resuming session $id..."
        my-claude-code-wrapper --resume "$id"
    end
end

function _ccs_help
    echo "ccs [add|list|rm|open|help]"
    echo "  add <id> [title]   Add a session (also accepts 'claude --resume <id>')"
    echo "  list               List sessions in current directory"
    echo "  remove <id>        Remove a session"
    echo "  resume             Pick and resume a session (fzf)"
    echo "  help               Show this help"
end

function ccs --description 'Claude Code Sessions - manage per-directory sessions'
    switch "$argv[1]"
        case add
            _ccs_add $argv[2..-1]
        case list ls
            _ccs_list
        case remove
            _ccs_remove $argv[2..-1]
        case resume ''
            _ccs_open
        case help -h --help
            _ccs_help
        case '*'
            _ccs_help
    end
end
