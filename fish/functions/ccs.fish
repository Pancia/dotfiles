function _ccs_file
    echo (pwd)"/.claude-sessions"
end

# All session data goes through jq. Each line is: {"id":"...","ts":"...","title":"..."}

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

    set -l ts (date '+%Y-%m-%d %H:%M')
    set -l file (_ccs_file)

    # Remove existing entry with same id
    if test -f "$file"
        set -l tmp (jq -c "select(.id != \"$id\")" "$file" 2>/dev/null)
        printf '%s\n' $tmp > "$file"
    end

    # Append new entry
    jq -cn --arg id "$id" --arg ts "$ts" --arg title "$title" \
        '{id: $id, ts: $ts, title: $title}' >> "$file"

    if test -n "$title"
        echo "Added session: $id ($ts — $title)"
    else
        echo "Added session: $id ($ts)"
    end
end

function _ccs_list --description 'List claude sessions'
    set -l file (_ccs_file)
    if not test -f "$file"
        return 1
    end
    set -l entries (jq -r '[.id, .ts, .title] | @tsv' "$file" 2>/dev/null)
    if test -z "$entries"
        return 1
    end
    for entry in $entries
        set -l parts (string split \t "$entry")
        set -l id $parts[1]
        set -l ts $parts[2]
        set -l title $parts[3]
        set -l meta
        if test -n "$ts" -a -n "$title"
            set meta "$ts — $title"
        else if test -n "$ts"
            set meta "$ts"
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
    set -l tmp (jq -c "select(.id != \"$id\")" "$file" 2>/dev/null)
    printf '%s\n' $tmp > "$file"
    echo "Removed session $id"
end

function _ccs_rename --description 'Rename a claude session'
    set -l id $argv[1]
    set -l new_title (string join ' ' $argv[2..-1])
    if test -z "$id" -o -z "$new_title"
        echo "Usage: ccs rename <id> <new title>"
        return 1
    end
    set -l file (_ccs_file)
    if not test -f "$file"
        echo "No .claude-sessions file"
        return 1
    end

    set -l before (cat "$file")
    jq -c --arg id "$id" --arg title "$new_title" \
        'if .id == $id then .title = $title else . end' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"

    # Check if anything changed
    if test "$before" = (cat "$file")
        echo "Session $id not found"
        return 1
    end
    echo "Renamed session $id -> $new_title"
end

function _ccs_session_jsonl --description 'Find the JSONL file for a session ID'
    set -l id $argv[1]
    set -l project_dir (string replace -a '/' '-' (pwd))
    set -l jsonl "$HOME/.claude/projects/$project_dir/$id.jsonl"
    if test -f "$jsonl"
        echo "$jsonl"
        return 0
    end
    return 1
end

function _ccs_extract_messages --description 'Extract text messages from a session JSONL'
    set -l jsonl $argv[1]
    python3 -c '
import json, sys
msgs = []
with open(sys.argv[1]) as f:
    for line in f:
        try:
            rec = json.loads(line)
        except:
            continue
        msg = rec.get("message", {})
        role = msg.get("role")
        if role not in ("user", "assistant"):
            continue
        content = msg.get("content", "")
        texts = []
        if isinstance(content, str):
            texts.append(content)
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    texts.append(block["text"])
        for t in texts:
            # skip huge content (diffs, system prompts, etc)
            if len(t) > 1000:
                t = t[:500] + "..."
            if t.strip():
                prefix = "Human" if role == "user" else "Assistant"
                msgs.append(f"{prefix}: {t}")
# Keep it reasonable for haiku - first and last few messages
if len(msgs) > 12:
    msgs = msgs[:6] + ["..."] + msgs[-4:]
print("\n".join(msgs))
' "$jsonl"
end

function _ccs_autotitle --description 'Auto-generate a title for a session using Haiku'
    set -l id $argv[1]
    if test -z "$id"
        # If no id given, let user pick
        set -l file (_ccs_file)
        if not test -f "$file"
            echo "No .claude-sessions file"
            return 1
        end
        set -l lines (jq -r '[.id, .ts, .title] | @tsv' "$file" 2>/dev/null)
        if test -z "$lines"
            echo "No sessions"
            return 1
        end
        set -l choice (printf '%s\n' $lines | fzf --prompt="Autotitle session> " --no-sort)
        if test -z "$choice"
            return 1
        end
        set id (string split \t "$choice")[1]
    end

    set -l jsonl (_ccs_session_jsonl "$id")
    if test $status -ne 0
        echo "Session JSONL not found for $id"
        return 1
    end

    set -l messages (_ccs_extract_messages "$jsonl")
    if test -z "$messages"
        echo "No messages found in session"
        return 1
    end

    echo "Generating title..."
    set -l title (printf '%s\n' $messages | claude -p --model haiku --system-prompt "You generate short titles for conversations. Reply with ONLY the title (3-8 words, no quotes), nothing else." "What is a good title for this conversation?")

    if test -z "$title"
        echo "Failed to generate title"
        return 1
    end

    echo "Suggested title: $title"
    read -P "Apply? [Y/n] " -l confirm
    if test -z "$confirm" -o "$confirm" = y -o "$confirm" = Y
        _ccs_rename "$id" "$title"
    else
        echo "Cancelled"
    end
end

function _ccs_open --description 'Pick and resume a session'
    set -l file (_ccs_file)
    if not test -f "$file"
        echo "No .claude-sessions file"
        return 1
    end
    set -l lines (jq -r '[.id, .ts, .title] | @tsv' "$file" 2>/dev/null)
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
    echo "ccs [add|list|rename|autotitle|rm|resume|help]"
    echo "  add <id> [title]    Add a session (also accepts 'claude --resume <id>')"
    echo "  list                List sessions in current directory"
    echo "  rename <id> <title> Rename a session"
    echo "  autotitle [id]      Auto-generate a title using Haiku"
    echo "  remove <id>         Remove a session"
    echo "  resume              Pick and resume a session (fzf)"
    echo "  help                Show this help"
end

function ccs --description 'Claude Code Sessions - manage per-directory sessions'
    switch "$argv[1]"
        case add
            _ccs_add $argv[2..-1]
        case list ls
            _ccs_list
        case rename mv
            _ccs_rename $argv[2..-1]
        case autotitle at
            _ccs_autotitle $argv[2..-1]
        case remove rm
            _ccs_remove $argv[2..-1]
        case resume ''
            _ccs_open
        case help -h --help
            _ccs_help
        case '*'
            _ccs_help
    end
end
