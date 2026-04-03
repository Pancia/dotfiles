function _ccs_file
    echo (pwd)"/.cc/sessions.json"
end

# All session data goes through jq. File is a JSON array of {id, ts, title} objects.

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

    # Build new entry
    set -l new_entry (jq -cn --arg id "$id" --arg ts "$ts" --arg title "$title" \
        '{id: $id, ts: $ts, title: $title}')

    mkdir -p (dirname "$file")

    # Remove existing entry with same id, append new
    if test -f "$file"
        jq -c --arg id "$id" --argjson entry "$new_entry" \
            '[.[] | select(.id != $id)] + [$entry]' "$file" > "$file.tmp"
        mv "$file.tmp" "$file"
    else
        echo "[$new_entry]" > "$file"
    end

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
    set -l entries (jq -r '.[] | [.id, .title, .ts] | @tsv' "$file" 2>/dev/null | string collect)
    if test -z "$entries"
        return 1
    end
    for entry in (string split \n "$entries")
        set -l parts (string split \t "$entry")
        set -l id $parts[1]
        set -l title $parts[2]
        set -l ts $parts[3]
        set -l meta
        if test -n "$title" -a -n "$ts"
            set meta "$title — $ts"
        else if test -n "$title"
            set meta "$title"
        else if test -n "$ts"
            set meta "$ts"
        end
        set -l short_id (string sub -l 8 "$id")
        if test -n "$meta"
            printf '  %s  %s\n' (set_color cyan)"$short_id"(set_color normal) (set_color brblack)"$meta"(set_color normal)
        else
            printf '  %s\n' (set_color cyan)"$short_id"(set_color normal)
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
        echo "No sessions file"
        return 1
    end
    jq -c --arg id "$id" '[.[] | select(.id != $id)]' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
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
        echo "No sessions file"
        return 1
    end

    set -l before (string collect < "$file")
    jq -c --arg id "$id" --arg title "$new_title" \
        '[.[] | if .id == $id then .title = $title else . end]' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"

    # Check if anything changed
    if test "$before" = (string collect < "$file")
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
    # Parse --yes flag
    set -l auto_apply 0
    set -l id
    for arg in $argv
        switch $arg
            case -y --yes
                set auto_apply 1
            case '*'
                set id $arg
        end
    end
    if test -z "$id"
        # If no id given, let user pick
        set -l file (_ccs_file)
        if not test -f "$file"
            echo "No sessions file"
            return 1
        end
        set -l lines (jq -r '.[] | [.id, (.id | .[0:8]), .title, .ts] | @tsv' "$file" 2>/dev/null)
        if test -z "$lines"
            echo "No sessions"
            return 1
        end
        set -l choice (printf '%s\n' $lines | fzf --with-nth=2.. --prompt="Autotitle session> " --no-sort)
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
    set -l raw (printf '%s\n' $messages | claude -p --model haiku --output-format json \
        --system-prompt 'Output ONLY valid JSON: {"title":"<3-8 word title>"}. No markdown, no fences, no explanation, no extra text. Your entire response must be exactly one JSON object and nothing else.' \
        "Generate a title for this conversation." 2>/dev/null)
    # Extract .result from claude JSON envelope, then parse .title from Haiku's response
    set -l title (echo "$raw" | jq -r '.result | fromjson | .title' 2>/dev/null)
    # Fallback: try .result directly as plain text
    if test -z "$title" -o "$title" = null
        set title (echo "$raw" | jq -r '.result' 2>/dev/null | string replace -r '```json?\s*' '' | string replace -r '```\s*' '' | string replace -r '^["{]+' '' | string replace -r '["}]+$' '' | string trim)
    end
    # Final fallback: strip any remaining JSON fragments
    if string match -q '*title*:*' "$title"
        set title (echo "$title" | string replace -r '.*"title"\s*:\s*"' '' | string replace -r '".*' '')
    end

    if test -z "$title" -o "$title" = null
        echo "Failed to generate title"
        return 1
    end

    if test $auto_apply -eq 1
        echo "Title: $title"
        _ccs_rename "$id" "$title"
    else
        echo "Suggested title: $title"
        read -P "Apply? [Y/n] " -l confirm
        if test -z "$confirm" -o "$confirm" = y -o "$confirm" = Y
            _ccs_rename "$id" "$title"
        else
            echo "Cancelled"
        end
    end
end

function _ccs_open --description 'Pick and resume a session'
    set -l file (_ccs_file)
    if not test -f "$file"
        echo "No sessions file"
        return 1
    end
    set -l lines (jq -r '.[] | [.id, (.id | .[0:8]), .title, .ts] | @tsv' "$file" 2>/dev/null)
    if test -z "$lines"
        echo "No sessions"
        return 1
    end

    set -l choice (printf '%s\n' $lines | fzf --with-nth=2.. --prompt="Claude session> " --no-sort)
    if test -n "$choice"
        set -l id (string split \t "$choice")[1]
        echo "Resuming session $id..."
        my-claude-code-wrapper --resume "$id"
    end
end

function _ccs_backup_session --description 'Back up a single session JSONL as zstd'
    set -l id $argv[1]
    set -l jsonl (_ccs_session_jsonl "$id")
    if test $status -ne 0
        return 1
    end

    set -l backup_dir (pwd)"/.cc/session-backups"
    set -l backup "$backup_dir/$id.jsonl.zst"
    mkdir -p "$backup_dir"

    # Skip if backup is newer than source
    if test -f "$backup"
        set -l src_mtime (stat -f %m "$jsonl")
        set -l bak_mtime (stat -f %m "$backup")
        if test "$bak_mtime" -ge "$src_mtime"
            return 0
        end
    end

    zstd -qf "$jsonl" -o "$backup"
end

function _ccs_backup --description 'Back up all saved session JSONLs'
    set -l file (_ccs_file)
    if not test -f "$file"
        echo "No sessions file"
        return 1
    end

    set -l ids (jq -r '.[].id' "$file" 2>/dev/null)
    if test -z "$ids"
        echo "No sessions"
        return 1
    end

    set -l backed 0
    set -l skipped 0
    set -l missing 0
    for id in $ids
        _ccs_backup_session "$id"
        set -l exit_code $status
        if test $exit_code -eq 0
            set backed (math $backed + 1)
        else
            set missing (math $missing + 1)
        end
    end

    echo "Backup: $backed OK, $missing not found"
end

function _ccs_migrate --description 'Migrate .claude-sessions JSONL to .cc/sessions.json'
    set -l old_file (pwd)"/.claude-sessions"
    set -l new_file (_ccs_file)

    if not test -f "$old_file"
        echo "No .claude-sessions file to migrate"
        return 1
    end

    if not test -s "$old_file"
        echo "Empty .claude-sessions file"
        rm "$old_file"
        return 0
    end

    mkdir -p (dirname "$new_file")

    # Convert JSONL to JSON array
    set -l migrated (jq -sc '[.[] | select(. != null)]' "$old_file")

    if test -f "$new_file"
        # Merge: existing entries take precedence on id conflict
        jq -c --argjson old "$migrated" \
            '($old + .) | group_by(.id) | map(last)' "$new_file" > "$new_file.tmp"
        mv "$new_file.tmp" "$new_file"
    else
        echo "$migrated" > "$new_file"
    end

    # Only delete old file if new file is valid JSON
    if jq empty "$new_file" 2>/dev/null
        echo "Migrated "(jq 'length' "$new_file")" sessions to .cc/sessions.json"
        rm "$old_file"
        echo "Removed .claude-sessions"
    else
        echo "Migration may have failed — keeping .claude-sessions"
        return 1
    end
end

function _ccs_help
    echo "ccs [add|list|rename|autotitle|rm|resume|backup|migrate|help]"
    echo "  add <id> [title]    Add a session (also accepts 'claude --resume <id>')"
    echo "  list                List sessions in current directory"
    echo "  rename <id> <title> Rename a session"
    echo "  autotitle [id]      Auto-generate a title using Haiku"
    echo "  remove <id>         Remove a session"
    echo "  resume              Pick and resume a session (fzf)"
    echo "  backup              Back up saved session transcripts (zstd)"
    echo "  migrate             Migrate .claude-sessions to .cc/sessions.json"
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
        case backup
            _ccs_backup
        case migrate
            _ccs_migrate
        case help -h --help
            _ccs_help
        case '*'
            _ccs_help
    end
end
