function _ccs_file
    echo "$HOME/Cloud/cc-sessions"(pwd)"/sessions.json"
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
    # Open entries (running + crashed) — TSV: klass id file started term
    set -l open_lines (_ccs_open_scan)

    set -l running_lines
    set -l crashed_lines
    set -l running_ids
    for line in $open_lines
        set -l parts (string split \t -- $line)
        switch $parts[1]
            case running
                set -a running_lines $line
                set -a running_ids $parts[2]
            case crashed
                set -a crashed_lines $line
        end
    end

    # Saved entries (sanitize tabs in titles — @tsv would otherwise escape them
    # to literal "\t" in the display)
    set -l file (_ccs_file)
    set -l saved_lines
    if test -f "$file"
        set saved_lines (jq -r '.[] | [.id, (.title | gsub("\t"; " ")), .ts] | @tsv' "$file" 2>/dev/null)
    end

    set -l have_running (count $running_lines)
    set -l have_crashed (count $crashed_lines)
    set -l have_saved (count $saved_lines)

    if test $have_running -eq 0 -a $have_crashed -eq 0 -a $have_saved -eq 0
        return 1
    end

    set -l printed_any 0

    if test $have_running -gt 0
        echo (set_color brblack)"  Open (running)"(set_color normal)
        for line in $running_lines
            set -l parts (string split \t -- $line)
            set -l sid $parts[2]
            set -l started $parts[4]
            set -l term $parts[5]
            set -l short_id (string sub -l 8 "$sid")
            set -l when (date -r "$started" '+%H:%M' 2>/dev/null)
            set -l also_saved ""
            if test -f "$file"
                set -l in_saved (jq -r --arg id "$sid" '[.[].id] | index($id) // empty' "$file" 2>/dev/null)
                if test -n "$in_saved"
                    set also_saved " (also saved)"
                end
            end
            printf '  %s  %s  %s\n' \
                (set_color green)"●"(set_color normal) \
                (set_color cyan)"$short_id"(set_color normal) \
                (set_color brblack)"running since $when, $term$also_saved"(set_color normal)
        end
        set printed_any 1
    end

    if test $have_crashed -gt 0
        test $printed_any -eq 1; and echo ""
        echo (set_color brblack)"  Open (unrecovered)"(set_color normal)
        for line in $crashed_lines
            set -l parts (string split \t -- $line)
            set -l sid $parts[2]
            set -l started $parts[4]
            set -l short_id (string sub -l 8 "$sid")
            set -l when (date -r "$started" '+%Y-%m-%d %H:%M' 2>/dev/null)
            printf '  %s  %s  %s\n' \
                (set_color yellow)"⚠"(set_color normal) \
                (set_color cyan)"$short_id"(set_color normal) \
                (set_color brblack)"crashed $when"(set_color normal)
        end
        set printed_any 1
    end

    if test $have_saved -gt 0
        # Dedup against running (skip saved entries whose id is currently running)
        set -l saved_to_show
        for entry in $saved_lines
            set -l parts (string split \t -- $entry)
            if contains $parts[1] $running_ids
                continue
            end
            set -a saved_to_show $entry
        end
        if test (count $saved_to_show) -gt 0
            if test $printed_any -eq 1
                echo ""
                echo (set_color brblack)"  Saved"(set_color normal)
            end
            for entry in $saved_to_show
                set -l parts (string split \t -- $entry)
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
    set -l conversation (printf '<conversation>\n%s\n</conversation>' (string join -- \n $messages))
    set -l raw (printf '%s' "$conversation" | claude -p --model haiku --output-format json \
        --system-prompt 'You generate short titles for conversations. Output ONLY valid JSON: {"title":"<3-8 word title>"}. No markdown, no fences, no explanation.' \
        "Generate a short 3-8 word title summarizing the above conversation." 2>/dev/null)
    # Extract .result, strip markdown fences, parse .title
    set -l result (echo "$raw" | jq -r '.result' 2>/dev/null)
    # Strip markdown code fences if present
    set result (echo "$result" | string replace -r '^\s*```json?\s*' '' | string replace -r '\s*```\s*$' '')
    set -l title (echo "$result" | jq -r '.title' 2>/dev/null)

    if test -z "$title" -o "$title" = null
        echo "Failed to generate title"
        return 1
    end

    if test (string length "$title") -gt 100
        echo "Generated title too long, rejecting"
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

function _ccs_open --description 'Pick and resume/switch to a session'
    # Open entries
    set -l open_lines (_ccs_open_scan)
    set -l running_ids

    # Build picker lines: <klass>\t<id>\t<entry_file>\t<short>\t<marker>\t<label>
    set -l picker_lines
    for line in $open_lines
        set -l parts (string split \t -- $line)
        set -l klass $parts[1]
        set -l sid $parts[2]
        set -l ef $parts[3]
        set -l started $parts[4]
        set -l term $parts[5]
        set -l short_id (string sub -l 8 "$sid")
        if test "$klass" = running
            set -a running_ids $sid
            set -l when (date -r "$started" '+%H:%M' 2>/dev/null)
            set -a picker_lines (printf '%s\t%s\t%s\t%s\t%s\t%s' \
                $klass $sid $ef $short_id "●" "running since $when, $term")
        else if test "$klass" = crashed
            set -l when (date -r "$started" '+%Y-%m-%d %H:%M' 2>/dev/null)
            set -a picker_lines (printf '%s\t%s\t%s\t%s\t%s\t%s' \
                $klass $sid $ef $short_id "⚠" "crashed $when")
        end
    end

    # Saved entries
    set -l file (_ccs_file)
    if test -f "$file"
        # User-supplied titles can contain tabs; sanitize before TSV embedding
        set -l saved_lines (jq -r '.[] | [.id, (.title | gsub("\t"; " ")), .ts] | @tsv' "$file" 2>/dev/null)
        for entry in $saved_lines
            set -l parts (string split \t -- $entry)
            set -l id $parts[1]
            set -l title $parts[2]
            set -l ts $parts[3]
            # Dedup: skip if currently running
            if contains $id $running_ids
                continue
            end
            set -l short_id (string sub -l 8 "$id")
            set -l meta
            if test -n "$title" -a -n "$ts"
                set meta "$title — $ts"
            else if test -n "$title"
                set meta "$title"
            else if test -n "$ts"
                set meta "$ts"
            end
            set -a picker_lines (printf '%s\t%s\t%s\t%s\t%s\t%s' \
                saved $id "" $short_id " " $meta)
        end
    end

    if test (count $picker_lines) -eq 0
        echo "No sessions"
        return 1
    end

    set -l choice (printf '%s\n' $picker_lines | fzf --with-nth=4.. --prompt="Claude session> " --no-sort --delimiter=\t)
    if test -z "$choice"
        return 1
    end

    set -l parts (string split \t -- $choice)
    set -l klass $parts[1]
    set -l sid $parts[2]
    set -l ef $parts[3]

    switch $klass
        case running
            _ccs_switch_to "$ef"
        case crashed
            _ccs_archive_entry "$ef"
            echo "Resuming session $sid..."
            my-claude-code-wrapper --resume "$sid"
        case saved
            echo "Resuming session $sid..."
            my-claude-code-wrapper --resume "$sid"
    end
end

function _ccs_backup_session --description 'Back up a single session JSONL as zstd'
    set -l id $argv[1]
    set -l jsonl (_ccs_session_jsonl "$id")
    if test $status -ne 0
        return 1
    end

    set -l backup_dir "$HOME/Cloud/cc-sessions"(pwd)"/session-backups"
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

# ===== Open-session tracking =====
# Tracks every interactive `my-claude-code-wrapper` invocation so sessions
# remain recoverable after crashes / power loss, and so live sessions in
# other terminals are visible. State directory:
#   $XDG_STATE_HOME/claude-sessions/{open,archive}

function _ccs_open_dir --description 'Directory holding active+crashed session entries'
    set -l base $XDG_STATE_HOME
    if test -z "$base"
        set base "$HOME/.local/state"
    end
    echo "$base/claude-sessions/open"
end

function _ccs_archive_dir --description 'Directory holding archived session entries'
    set -l base $XDG_STATE_HOME
    if test -z "$base"
        set base "$HOME/.local/state"
    end
    echo "$base/claude-sessions/archive"
end

function _ccs_open_register --description 'Register a new open session entry'
    set -l pid $argv[1]
    if test -z "$pid"
        return 1
    end
    set -l dir (_ccs_open_dir)
    mkdir -p "$dir"

    set -l now (date +%s)
    set -l lstart (ps -o lstart= -p $pid 2>/dev/null | string trim)
    set -l cwd (pwd)
    set -l tty_path (tty 2>/dev/null)
    set -l program $TERM_PROGRAM

    set -l tmux_socket
    set -l tmux_pid
    set -l tmux_session
    set -l tmux_pane $TMUX_PANE
    if set -q TMUX; and test -n "$TMUX"
        set -l tmux_parts (string split , -- $TMUX)
        set tmux_socket $tmux_parts[1]
        set tmux_pid $tmux_parts[2]
        set tmux_session (tmux display-message -p '#S' 2>/dev/null)
        if test -z "$program"
            set program tmux
        end
    end

    set -l file "$dir/$pid-$now.json"
    set -l tmp "$file.tmp.$fish_pid"
    jq -n \
        --argjson pid "$pid" \
        --arg lstart "$lstart" \
        --arg cwd "$cwd" \
        --argjson started_at "$now" \
        --arg program "$program" \
        --arg tmux_socket "$tmux_socket" \
        --arg tmux_pid "$tmux_pid" \
        --arg tmux_session "$tmux_session" \
        --arg tmux_pane "$tmux_pane" \
        --arg iterm_session "$ITERM_SESSION_ID" \
        --arg kitty_window "$KITTY_WINDOW_ID" \
        --arg tty "$tty_path" \
        '{
            pid: $pid,
            pid_lstart: $lstart,
            cwd: $cwd,
            started_at: $started_at,
            ended_at: null,
            session_id: "",
            terminal: {
                program: $program,
                tmux_socket: $tmux_socket,
                tmux_server_pid: $tmux_pid,
                tmux_session: $tmux_session,
                tmux_pane: $tmux_pane,
                iterm_session: $iterm_session,
                kitty_window: $kitty_window,
                tty: $tty
            }
        }' > "$tmp"
    and mv "$tmp" "$file"
    or rm -f "$tmp"
end

function _ccs_open_entry_for_pid --description 'Find the open file for a pid+lstart we currently own'
    set -l pid $argv[1]
    set -l dir (_ccs_open_dir)
    set -l current_lstart (ps -o lstart= -p $pid 2>/dev/null | string trim)
    for f in "$dir"/$pid-*.json
        if not test -f "$f"
            continue
        end
        set -l file_lstart (jq -r '.pid_lstart' "$f" 2>/dev/null)
        if test "$file_lstart" = "$current_lstart"
            echo "$f"
            return 0
        end
    end
    return 1
end

function _ccs_open_watch --description 'Background poller: claim the new JSONL for this session'
    set -l pid $argv[1]
    set -l pre_latest $argv[2]
    set -l dir (_ccs_open_dir)
    set -l project_dir (string replace -a '/' '-' (pwd))
    set -l sessions_dir "$HOME/.claude/projects/$project_dir"
    set -l entry_file (_ccs_open_entry_for_pid $pid)
    if test -z "$entry_file"
        return 1
    end

    set -l pre_mtime 0
    if test -n "$pre_latest"; and test -f "$pre_latest"
        set pre_mtime (stat -f %m "$pre_latest" 2>/dev/null)
    end

    for i in (seq 60)
        # If the wrapper has died (clean exit deleted the file, or crash) bail
        # out so we don't resurrect a deleted entry with stale data.
        if not test -f "$entry_file"
            return 0
        end
        if not kill -0 $pid 2>/dev/null
            return 0
        end
        if not test -d "$sessions_dir"
            sleep 1
            continue
        end
        # Find candidate JSONLs newer than pre_latest
        set -l candidates (find "$sessions_dir" -maxdepth 1 -name '*.jsonl' -type f -exec stat -f '%m %N' {} + 2>/dev/null | sort -n | awk -v t=$pre_mtime '$1 > t {print $2}')
        if test (count $candidates) -gt 0
            # Read all sibling session_ids to avoid double-claiming
            set -l claimed
            for sf in "$dir"/*.json
                test -f "$sf"; or continue
                set -l sid (jq -r '.session_id // ""' "$sf" 2>/dev/null)
                if test -n "$sid"
                    set -a claimed $sid
                end
            end
            for cand in $candidates
                set -l cand_id (basename "$cand" .jsonl)
                if contains $cand_id $claimed
                    continue
                end
                # Verify via line 1 sessionId field for robustness
                set -l line1_id (head -n1 "$cand" 2>/dev/null | jq -r '.sessionId // empty' 2>/dev/null)
                if test -n "$line1_id"
                    set cand_id $line1_id
                    if contains $cand_id $claimed
                        continue
                    end
                end
                # Claim it. Re-check entry_file right before mv so we don't
                # resurrect an entry the wrapper has just deleted on clean exit.
                set -l tmp "$entry_file.tmp.$fish_pid"
                jq --arg id "$cand_id" '.session_id = $id' "$entry_file" > "$tmp"
                or begin
                    rm -f "$tmp"
                    return 1
                end
                if not test -f "$entry_file"
                    rm -f "$tmp"
                    return 0
                end
                mv "$tmp" "$entry_file"
                return 0
            end
        end
        sleep 1
    end
    return 1
end

function _ccs_open_finalize --description 'Delete the open entry for this pid (clean exit)'
    set -l pid $argv[1]
    set -l entry_file (_ccs_open_entry_for_pid $pid)
    if test -n "$entry_file"
        rm -f "$entry_file"
    end
end

function _ccs_open_alive --description 'True iff entry file points at a live process (PID + lstart match)'
    set -l entry_file $argv[1]
    test -f "$entry_file"; or return 1
    set -l pid (jq -r '.pid' "$entry_file" 2>/dev/null)
    set -l lstart (jq -r '.pid_lstart' "$entry_file" 2>/dev/null)
    if test -z "$pid" -o "$pid" = null
        return 1
    end
    if not kill -0 $pid 2>/dev/null
        return 1
    end
    set -l current_lstart (ps -o lstart= -p $pid 2>/dev/null | string trim)
    test "$current_lstart" = "$lstart"
end

function _ccs_open_scan --description 'Classify open entries for current pwd; reap garbage; print TSV'
    set -l dir (_ccs_open_dir)
    test -d "$dir"; or return 0
    set -l cwd (pwd)
    set -l now (date +%s)
    set -l garbage_age (math 5 \* 60)
    for f in "$dir"/*.json
        test -f "$f"; or continue
        set -l entry_cwd (jq -r '.cwd' "$f" 2>/dev/null)
        if test "$entry_cwd" != "$cwd"
            continue
        end
        set -l sid (jq -r '.session_id // ""' "$f" 2>/dev/null)
        set -l started (jq -r '.started_at // 0' "$f" 2>/dev/null)
        set -l klass
        if _ccs_open_alive "$f"
            set klass running
        else if test -z "$sid"; and test (math "$now - $started") -gt $garbage_age
            # Garbage: dead, no session_id, > 5 min old
            rm -f "$f"
            continue
        else if test -z "$sid"
            # Dead but recent: skip (watcher may still be running)
            continue
        else
            set klass crashed
        end

        # Build a short terminal summary. Defaults to "shell" so the picker
        # never shows a trailing comma with no program name.
        set -l program (jq -r '.terminal.program // "shell"' "$f" 2>/dev/null)
        set -l tmux_session (jq -r '.terminal.tmux_session // ""' "$f" 2>/dev/null)
        set -l tmux_pane (jq -r '.terminal.tmux_pane // ""' "$f" 2>/dev/null)
        set -l term_summary $program
        if test -n "$tmux_session"
            set term_summary "$program $tmux_session:$tmux_pane"
        end
        # Sanitize tabs from user/env-supplied fields so TSV stays well-formed
        set term_summary (string replace -a \t ' ' -- $term_summary)

        printf '%s\t%s\t%s\t%s\t%s\n' "$klass" "$sid" "$f" "$started" "$term_summary"
    end
end

function _ccs_switch_to --description 'Best-effort focus the terminal running a session'
    set -l entry_file $argv[1]
    test -f "$entry_file"; or return 1
    set -l pid (jq -r '.pid' "$entry_file")
    set -l tty_path (jq -r '.terminal.tty // ""' "$entry_file")
    set -l started_at (jq -r '.started_at' "$entry_file")

    # tmux
    set -l tmux_pid (jq -r '.terminal.tmux_server_pid // ""' "$entry_file")
    set -l tmux_socket (jq -r '.terminal.tmux_socket // ""' "$entry_file")
    set -l tmux_session (jq -r '.terminal.tmux_session // ""' "$entry_file")
    set -l tmux_pane (jq -r '.terminal.tmux_pane // ""' "$entry_file")
    if test -n "$tmux_pid"; and test -n "$tmux_socket"; and kill -0 $tmux_pid 2>/dev/null
        if tmux -S "$tmux_socket" switch-client -t "$tmux_session" 2>/dev/null
            tmux -S "$tmux_socket" select-pane -t "$tmux_pane" 2>/dev/null
            return 0
        end
    end

    # iTerm
    set -l iterm_session (jq -r '.terminal.iterm_session // ""' "$entry_file")
    if test -n "$iterm_session"
        set -l script 'tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if id of s is "'$iterm_session'" then
                            select s
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell'
        if osascript -e "$script" 2>/dev/null
            return 0
        end
    end

    # Kitty
    set -l kitty_window (jq -r '.terminal.kitty_window // ""' "$entry_file")
    if test -n "$kitty_window"
        if kitten @ focus-window --match "id:$kitty_window" 2>/dev/null
            return 0
        end
    end

    # Fallback
    set -l started_h (date -r "$started_at" '+%Y-%m-%d %H:%M' 2>/dev/null)
    echo (set_color yellow)"Session running as PID $pid on $tty_path (started $started_h)"(set_color normal)
    echo "Could not auto-switch; bring that window to focus manually."
end

function _ccs_archive_entry --description 'Move an open entry into the archive'
    set -l entry_file $argv[1]
    test -f "$entry_file"; or return 1
    set -l archive (_ccs_archive_dir)
    mkdir -p "$archive"
    mv "$entry_file" "$archive/"
end

function _ccs_old --description 'List archived (resumed) session entries for current pwd'
    set -l archive (_ccs_archive_dir)
    if not test -d "$archive"
        echo "No archived sessions"
        return 1
    end
    set -l cwd (pwd)
    # Build epoch-prefixed sortable list, newest first
    set -l rows
    for f in "$archive"/*.json
        test -f "$f"; or continue
        set -l entry_cwd (jq -r '.cwd' "$f" 2>/dev/null)
        if test "$entry_cwd" != "$cwd"
            continue
        end
        set -l started (jq -r '.started_at // 0' "$f" 2>/dev/null)
        set -l sid (jq -r '.session_id // ""' "$f" 2>/dev/null)
        set -a rows (printf '%s\t%s\t%s' $started $sid $f)
    end
    if test (count $rows) -eq 0
        echo "No archived sessions for this directory"
        return 1
    end
    printf '%s\n' $rows | sort -rn | while read -l line
        set -l parts (string split \t -- $line)
        set -l started $parts[1]
        set -l sid $parts[2]
        set -l short_id (string sub -l 8 "$sid")
        set -l when (date -r "$started" '+%Y-%m-%d %H:%M' 2>/dev/null)
        printf '  %s  %s\n' (set_color cyan)"$short_id"(set_color normal) (set_color brblack)"archived $when"(set_color normal)
    end
end

function _ccs_migrate --description 'Migrate old session files to ~/Cloud/cc-sessions/'
    set -l new_file (_ccs_file)
    set -l migrated_any 0

    # Try both old locations
    for old_file in (pwd)"/.claude-sessions" (pwd)"/.cc/sessions.json"
        if not test -f "$old_file"
            continue
        end

        if not test -s "$old_file"
            echo "Empty $old_file, removing"
            rm "$old_file"
            continue
        end

        mkdir -p (dirname "$new_file")

        # Detect format: JSONL (.claude-sessions) vs JSON array (.cc/sessions.json)
        set -l old_data
        if string match -q '*.claude-sessions' "$old_file"
            set old_data (jq -sc '[.[] | select(. != null)]' "$old_file")
        else
            set old_data (cat "$old_file")
        end

        if test -f "$new_file"
            jq -c --argjson old "$old_data" \
                '($old + .) | group_by(.id) | map(last)' "$new_file" > "$new_file.tmp"
            mv "$new_file.tmp" "$new_file"
        else
            echo "$old_data" > "$new_file"
        end

        if jq empty "$new_file" 2>/dev/null
            set -l count (jq 'length' "$new_file")
            echo "Migrated $old_file ($count sessions)"
            rm "$old_file"
            set migrated_any 1
        else
            echo "Migration may have failed — keeping $old_file"
        end
    end

    # Migrate session backups
    set -l old_backups (pwd)"/.cc/session-backups"
    if test -d "$old_backups"
        set -l new_backups (dirname "$new_file")"/session-backups"
        mkdir -p "$new_backups"
        for f in "$old_backups"/*.jsonl.zst
            if test -f "$f"
                mv "$f" "$new_backups/"
                set migrated_any 1
            end
        end
        rmdir "$old_backups" 2>/dev/null
        and echo "Migrated session backups"
    end

    if test $migrated_any -eq 0
        echo "Nothing to migrate"
        return 1
    end
end

function _ccs_help
    echo "ccs [add|list|rename|autotitle|rm|resume|old|backup|migrate|help]"
    echo "  add <id> [title]    Add a session (also accepts 'claude --resume <id>')"
    echo "  list                List sessions in current directory"
    echo "  rename <id> <title> Rename a session"
    echo "  autotitle [id]      Auto-generate a title using Haiku"
    echo "  remove <id>         Remove a session"
    echo "  resume              Pick and resume a session (fzf)"
    echo "  old                 List archived (previously-resumed) sessions"
    echo "  backup              Back up saved session transcripts (zstd)"
    echo "  migrate             Migrate old .claude-sessions/.cc/ to ~/Cloud/cc-sessions/"
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
        case old archive
            _ccs_old
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
