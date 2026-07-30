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
        set saved_lines (jq -r '.[] | [.id, (.title // "" | gsub("\t"; " ")), .ts] | @tsv' "$file" 2>/dev/null)
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
            set -l title $parts[6]
            set -l meta "running since $when, $term$also_saved"
            if test -n "$title"
                set meta "$title — running since $when, $term$also_saved"
            end
            printf '  %s  %s  %s\n' \
                (set_color green)"●"(set_color normal) \
                (set_color cyan)"$short_id"(set_color normal) \
                (set_color brblack)"$meta"(set_color normal)
        end
        set printed_any 1
    end

    if test $have_crashed -gt 0
        test $printed_any -eq 1; and echo ""
        echo (set_color brblack)"  Open (unrecovered)"(set_color normal)
        # _ccs_open_scan already emits newest-first
        for line in $crashed_lines
            set -l parts (string split \t -- $line)
            set -l sid $parts[2]
            set -l started $parts[4]
            set -l short_id (string sub -l 8 "$sid")
            set -l when (date -r "$started" '+%Y-%m-%d %H:%M' 2>/dev/null)
            set -l title $parts[6]
            set -l meta "crashed $when"
            if test -n "$title"
                set meta "$title — $when"
            end
            printf '  %s  %s  %s\n' \
                (set_color yellow)"⚠"(set_color normal) \
                (set_color cyan)"$short_id"(set_color normal) \
                (set_color brblack)"$meta"(set_color normal)
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
    # Capture into a variable rather than comparing against a substitution: on a
    # zero-byte sessions.json the substitution yields no elements at all, and
    # `test` then errors out and reports a rename that never happened.
    set -l after (string collect < "$file")

    # Not a saved session? It may still be a crashed/archived open entry, whose
    # title lives in the entry file instead. Without this, retitling anything
    # that isn't in sessions.json fails outright.
    if test "$before" = "$after"
        if _ccs_entry_set_title "$id" "$new_title"
            echo "Renamed session $id -> $new_title"
            return 0
        end
        echo "Session $id not found"
        return 1
    end
    echo "Renamed session $id -> $new_title"
end

function _ccs_entry_set_title --description 'Record a title on an open/archived session entry'
    set -l id $argv[1]
    set -l title $argv[2]
    test -n "$id"; or return 1
    test -n "$title"; or return 1

    # Write to EVERY entry with this id, not just the first found. Duplicate
    # entries for one session do occur, and the scan displays whichever has the
    # newest started_at — stopping at the first match would silently title the
    # row you can't see.
    set -l wrote 0
    for dir in (_ccs_open_dir) (_ccs_archive_dir)
        test -d "$dir"; or continue
        for f in "$dir"/*.json
            test -f "$f"; or continue
            set -l sid (jq -r '.session_id // ""' "$f" 2>/dev/null)
            if test "$sid" != "$id"
                continue
            end
            set -l tmp "$f.tmp.$fish_pid"
            # Flag it manual, or the Stop hook overwrites it with the
            # Claude-generated title on the very next turn. The begin/end wrapper
            # catches fish's own redirect failure on a read-only state dir —
            # a trailing 2>/dev/null only covers jq's stderr, not the redirect.
            if begin
                    jq --arg t "$title" '.title = $t | .title_manual = true' "$f" > "$tmp"
                end 2>/dev/null
                # Re-check: a clean exit may have removed the entry meanwhile
                if test -f "$f"
                    mv "$tmp" "$f"
                    set wrote 1
                else
                    rm -f "$tmp"
                end
            else
                rm -f "$tmp"
            end
        end
    end
    test $wrote -eq 1
end

function _ccs_session_jsonl --description 'Find the JSONL file for a session ID'
    set -l id $argv[1]
    test -n "$id"; or return 1
    # Glob rather than deriving the project dir from (pwd): Claude Code mangles
    # '.' as well as '/' (~/.claude/projects -> -Users-anthony--claude-projects)
    # and the full rule isn't documented, so deriving it silently misses sessions.
    for f in "$HOME"/.claude/projects/*/"$id".jsonl
        if test -f "$f"
            echo "$f"
            return 0
        end
    end
    return 1
end

function _ccs_truncate --description 'Truncate a string to a display width'
    set -l s $argv[1]
    set -l max $argv[2]
    # printf, not echo: a title of exactly "-e" or "-n" would be eaten as a flag
    if test (string length -- "$s") -gt $max
        printf '%s…\n' (string sub -l (math $max - 1) -- "$s")
    else
        printf '%s\n' "$s"
    end
end

function _ccs_session_title --description 'Read a session title out of its transcript'
    set -l id $argv[1]
    set -l entry_file $argv[2]

    # Prefer the title the Stop hook recorded while the session was alive: it
    # survives the transcript being pruned, and saves re-reading a large file
    # on every `cd` (ccs list runs from chpwd).
    if test -n "$entry_file"; and test -f "$entry_file"
        set -l cached (jq -r '.title // empty' "$entry_file" 2>/dev/null)
        if test -n "$cached"
            _ccs_truncate "$cached" 58
            return 0
        end
    end

    set -l jsonl (_ccs_session_jsonl "$id")
    or return 1

    # Claude Code writes its own generated title as {"type":"ai-title","aiTitle":...},
    # refreshed as the session drifts, so the last record is current. Decode with
    # jq rather than slicing between quotes: a title containing an escaped quote
    # would be cut mid-escape and left with a trailing backslash. Conversational
    # mentions of the field are JSON-escaped, so the grep can't match them.
    # The type guard keeps a non-string field from being flattened into a bogus
    # title: jq -r on an array emits one element per line, which the command
    # substitution below would silently join into nonsense.
    set -l raw (grep '"type":"ai-title"' "$jsonl" 2>/dev/null | tail -1 \
        | jq -r 'if (.aiTitle | type) == "string" then .aiTitle else empty end' 2>/dev/null)

    if test -z "$raw"
        # Fall back to the last user prompt, for sessions Claude never titled
        set raw (grep '"type":"last-prompt"' "$jsonl" 2>/dev/null | tail -1 \
            | jq -r 'if (.lastPrompt | type) == "string" then .lastPrompt else empty end' 2>/dev/null)
    end

    set -l title (string join ' ' $raw)
    test -n "$title"; or return 1

    # Collapse to a single display line
    set title (string replace -ra '\s+' ' ' -- "$title" | string trim)
    test -n "$title"; or return 1
    _ccs_truncate "$title" 58
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
    # Both `string collect` calls are load-bearing. Without the inner one, the command
    # substitution re-splits the joined string on newlines, so printf cycles its format
    # once PER LINE and haiku receives one fake <conversation> block per line rather
    # than one block containing the conversation. Without the outer one, the capture
    # splits again and the interpolation below space-joins what is left.
    set -l conversation (printf '<conversation>\n%s\n</conversation>' (string join -- \n $messages | string collect) | string collect)
    # Route the envelope through a file: a command substitution reports the status of
    # `set`, not of the pipeline, and a timeout has to be distinguishable from a claude
    # error. claude-p only writes to stderr when it fails, so it is left unsuppressed.
    # --json-schema constrains the reply server-side, so the shape is not a request
    # the model can decline. That replaced a "no markdown, no fences, no explanation"
    # plea in the system prompt plus two fence-stripping `string replace` calls and a
    # double jq hop downstream; the schema-validated object arrives on
    # .structured_output, one jq away.
    set -l title_schema '{"type":"object","properties":{"title":{"type":"string","description":"A 3-8 word title summarizing the conversation"}},"required":["title"],"additionalProperties":false}'
    set -l rawfile (mktemp)
    printf '%s' "$conversation" | claude-p --model haiku --output-format json \
        --json-schema "$title_schema" \
        --system-prompt 'You generate short titles for conversations.' \
        "Generate a short 3-8 word title summarizing the above conversation." >$rawfile
    set -l status_code $status
    set -l title (jq -r '.structured_output.title // empty' $rawfile 2>/dev/null)
    rm -f $rawfile

    if test $status_code -eq 124
        echo "Title generation timed out"
        return 1
    end
    if test $status_code -ne 0
        echo "Title generation failed (claude exited $status_code)"
        return 1
    end

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
    # _ccs_open_scan already emits newest-first
    for line in $open_lines
        set -l parts (string split \t -- $line)
        set -l klass $parts[1]
        set -l sid $parts[2]
        set -l ef $parts[3]
        set -l started $parts[4]
        set -l term $parts[5]
        set -l short_id (string sub -l 8 "$sid")
        set -l title $parts[6]
        if test "$klass" = running
            set -a running_ids $sid
            set -l when (date -r "$started" '+%H:%M' 2>/dev/null)
            set -l label "running since $when, $term"
            if test -n "$title"
                set label "$title — running since $when, $term"
            end
            set -a picker_lines (printf '%s\t%s\t%s\t%s\t%s\t%s' \
                $klass $sid $ef $short_id "●" $label)
        else if test "$klass" = crashed
            set -l when (date -r "$started" '+%Y-%m-%d %H:%M' 2>/dev/null)
            set -l label "crashed $when"
            if test -n "$title"
                set label "$title — $when"
            end
            set -a picker_lines (printf '%s\t%s\t%s\t%s\t%s\t%s' \
                $klass $sid $ef $short_id "⚠" $label)
        end
    end

    # Saved entries
    set -l file (_ccs_file)
    if test -f "$file"
        # User-supplied titles can contain tabs; sanitize before TSV embedding
        set -l saved_lines (jq -r '.[] | [.id, (.title // "" | gsub("\t"; " ")), .ts] | @tsv' "$file" 2>/dev/null)
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
            # Claude Code eventually prunes transcripts; put ours back first, or
            # --resume has nothing to open. Must run before the entry is
            # archived, since it holds the path to restore to.
            if not _ccs_session_jsonl "$sid" >/dev/null
                if not _ccs_restore_transcript "$sid" "$ef"
                    echo (set_color yellow)"Transcript for $sid is gone and could not be restored — resume will likely fail."(set_color normal)
                end
            end
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

function _ccs_restore_transcript --description 'Put a crashed session transcript back so it can be resumed'
    set -l sid $argv[1]
    set -l entry_file $argv[2]
    test -n "$sid"; or return 1

    # Still present — nothing to do
    if _ccs_session_jsonl "$sid" >/dev/null
        return 0
    end

    # We can only restore to where the file actually belongs, and the only
    # reliable source for that is the path the Stop hook recorded from the hook
    # payload. Deriving the project dir name from cwd is not dependable, and
    # writing a transcript to the wrong dir would make it unresumable anyway.
    set -l target
    if test -n "$entry_file"; and test -f "$entry_file"
        set target (jq -r '.transcript_path // ""' "$entry_file" 2>/dev/null)
    end
    if test -z "$target"
        return 1
    end

    set -l backup (_ccs_local_backup_dir)"/$sid.jsonl.zst"
    if not test -f "$backup"
        set backup "$HOME/Cloud/cc-sessions"(jq -r '.cwd // ""' "$entry_file" 2>/dev/null)"/session-backups/$sid.jsonl.zst"
    end
    test -f "$backup"; or return 1

    mkdir -p (dirname "$target") 2>/dev/null
    if zstd -dqf "$backup" -o "$target" 2>/dev/null
        echo "Restored transcript from backup: "(basename "$target")
        return 0
    end
    return 1
end

function _ccs_local_backup_dir --description 'Local (non-cloud) transcript backups written by the Stop hook'
    set -l base $XDG_STATE_HOME
    if test -z "$base"
        set base "$HOME/.local/state"
    end
    echo "$base/claude-sessions/transcripts"
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
    # Echo the path so callers can export it as CCS_ENTRY_FILE for the hooks
    and echo "$file"
    or begin
        rm -f "$tmp"
        return 1
    end
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

function _ccs_open_finalize --description 'Delete the open entry for this pid (clean exit)'
    set -l pid $argv[1]
    set -l entry_file (_ccs_open_entry_for_pid $pid)
    test -n "$entry_file"; or return 0

    # If this session was saved but never titled, inherit the title the Stop
    # hook recorded — saves `ccsave` a Haiku round trip.
    set -l sid (jq -r '.session_id // ""' "$entry_file" 2>/dev/null)
    set -l title (jq -r '.title // ""' "$entry_file" 2>/dev/null)
    set -l saved (_ccs_file)
    if test -n "$sid"; and test -n "$title"; and test -f "$saved"
        set -l needs (jq -r --arg id "$sid" \
            'map(select(.id == $id and ((.title // "") == ""))) | length' "$saved" 2>/dev/null)
        if test "$needs" = 1
            set -l tmp "$saved.tmp.$fish_pid"
            if jq -c --arg id "$sid" --arg t "$title" \
                '[.[] | if .id == $id and ((.title // "") == "") then .title = $t else . end]' \
                "$saved" > "$tmp" 2>/dev/null
                mv "$tmp" "$saved"
            else
                rm -f "$tmp"
            end
        end
    end

    rm -f "$entry_file"
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
    # One python pass rather than a jq fork per field: this runs on every `cd`
    # via chpwd, and the old version spawned ~330 processes (~7s). Python also
    # tolerates a corrupt entry file — `jq -n inputs` aborts the whole stream on
    # the first parse error, silently truncating the session list.
    # Emits TSV: klass, session_id, entry_file, started_at, term_summary, title
    python3 -c '
import json, os, subprocess, sys

open_dir, want_cwd = sys.argv[1], sys.argv[2]
GARBAGE_AGE = 5 * 60
now = int(__import__("time").time())

# One ps call for every pid, instead of one per entry
alive = {}
try:
    out = subprocess.run(["ps", "-eo", "pid=,lstart="], capture_output=True, text=True).stdout
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        pid, _, lstart = line.partition(" ")
        alive[pid.strip()] = lstart.strip()
except Exception:
    pass

project_root = os.path.expanduser("~/.claude/projects")
try:
    project_dirs = [e.path for e in os.scandir(project_root) if e.is_dir()]
except OSError:
    project_dirs = []

def transcript_for(sid):
    # Glob rather than deriving the dir name from cwd: Claude Code mangles "."
    # as well as "/", and the full rule is not documented.
    for d in project_dirs:
        p = os.path.join(d, sid + ".jsonl")
        if os.path.isfile(p):
            return p
    return ""

def title_from(path):
    try:
        with open(path, "rb") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return ""
    # Claude Code records its own title as {"type":"ai-title","aiTitle":...},
    # refreshed as the session drifts, so the last record wins. Parse the whole
    # record rather than slicing between quotes: a title containing an escaped
    # quote would otherwise be cut mid-escape and yield a trailing backslash.
    # Falls back to the last user prompt for sessions Claude never titled.
    for key, field in ((b"\"type\":\"ai-title\"", "aiTitle"),
                       (b"\"type\":\"last-prompt\"", "lastPrompt")):
        for line in reversed(lines):
            if key not in line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            val = rec.get(field)
            # Must be a string: a lastPrompt array would otherwise be stored as
            # its JSON rendering and shown as the title.
            if isinstance(val, str) and val:
                return val
    return ""

def clean(s, limit=58):
    s = " ".join(str(s).split())
    if len(s) > limit:
        s = s[:limit - 1] + "…"
    return s

rows = []
try:
    names = sorted(os.listdir(open_dir))
except OSError:
    names = []

for name in names:
    if not name.endswith(".json"):
        continue
    path = os.path.join(open_dir, name)
    try:
        with open(path) as fh:
            e = json.load(fh)
    except Exception:
        # Corrupt or half-written: skip this entry, never the whole listing
        continue
    if not isinstance(e, dict):
        continue

    # Case-insensitive: some entries recorded Vaults/, others vaults/, and a
    # string compare hid whichever case you were not standing in.
    if str(e.get("cwd", "")).lower() != want_cwd.lower():
        continue

    sid = str(e.get("session_id") or "")
    try:
        started = int(e.get("started_at") or 0)
    except (TypeError, ValueError):
        started = 0
    pid = str(e.get("pid") or "")
    lstart = str(e.get("pid_lstart") or "")

    is_alive = bool(pid) and alive.get(pid) == lstart and lstart != ""
    if is_alive:
        klass = "running"
    elif not sid:
        if now - started > GARBAGE_AGE:
            # Dead and it never captured a session id: nothing recoverable
            try:
                os.remove(path)
            except OSError:
                pass
        continue
    else:
        klass = "crashed"

    term = e.get("terminal") or {}
    program = str(term.get("program") or "") or "shell"
    tmux_session = str(term.get("tmux_session") or "")
    tmux_pane = str(term.get("tmux_pane") or "")
    summary = "%s %s:%s" % (program, tmux_session, tmux_pane) if tmux_session else program

    # Prefer the title the Stop hook recorded while the session was alive: it
    # outlives the transcript, which Claude Code eventually prunes.
    title = str(e.get("title") or "")
    if not title and sid:
        p = str(e.get("transcript_path") or "")
        if not p or not os.path.isfile(p):
            p = transcript_for(sid)
        if p:
            title = title_from(p)

    rows.append((started, klass, sid, path, summary, title))

# Dedup only among real session ids. Several entries share the empty id — one of
# them can be the live session — so keying on it would collapse them into one row.
# Order running-first, then newest, and keep the FIRST per id: a dead entry with
# a newer started_at must never displace a live one, or `ccs list` would show a
# running session as crashed and `ccs resume` would start a second Claude on an
# already-open transcript instead of switching to its terminal.
best = {}
loose = []
for r in sorted(rows, key=lambda r: (r[1] != "running", -r[0])):
    sid = r[2]
    if not sid:
        loose.append(r)
    elif sid not in best:
        best[sid] = r

for started, klass, sid, path, summary, title in sorted(
        list(best.values()) + loose, key=lambda r: -r[0]):
    # Tabs and newlines would break the TSV contract downstream
    print("\t".join(clean(x, 400) if i < 4 else clean(x) for i, x in
                    enumerate([klass, sid, path, str(started), summary, title])))
' "$dir" (pwd)
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

function _ccs_prune --description 'Archive crashed entries that can no longer be recovered'
    set -l dry 0
    if contains -- --dry-run $argv; or contains -- -n $argv
        set dry 1
    end

    set -l dir (_ccs_open_dir)
    if not test -d "$dir"
        echo "No open sessions directory"
        return 1
    end
    set -l archive (_ccs_archive_dir)
    set -l local_backups (_ccs_local_backup_dir)

    set -l checked 0
    set -l pruned 0
    set -l kept 0

    # Deliberately sweeps every directory, not just (pwd): the scan only ever
    # sees entries for the directory you happen to be in.
    for f in "$dir"/*.json
        test -f "$f"; or continue
        # Never touch a live session
        if _ccs_open_alive "$f"
            continue
        end
        set -l sid (jq -r '.session_id // ""' "$f" 2>/dev/null)
        # No session id yet — leave those to the scan's garbage collection
        test -n "$sid"; or continue
        set checked (math $checked + 1)
        set -l entry_cwd (jq -r '.cwd // ""' "$f" 2>/dev/null)

        # Recoverable if ANY of three sources survives. Check all before
        # touching anything — an entry archived by mistake is a lost session.
        set -l recoverable 0
        # 1. the transcript itself
        if _ccs_session_jsonl "$sid" >/dev/null
            set recoverable 1
        end
        # 2. a compressed copy, local or cloud. Keep the entry whenever one
        #    exists: the conversation is still on disk, so archiving it would be
        #    throwing away the only copy's only pointer. Restoring it needs the
        #    transcript_path the Stop hook records, and entries predating that
        #    hook don't have one — that makes resume fail loudly, which is far
        #    better than silently discarding a recoverable session.
        if test $recoverable -eq 0
            if test -f "$local_backups/$sid.jsonl.zst"
                set recoverable 1
            else if test -f "$HOME/Cloud/cc-sessions$entry_cwd/session-backups/$sid.jsonl.zst"
                set recoverable 1
            end
        end
        # 3. recorded as a saved session
        if test $recoverable -eq 0
            set -l saved "$HOME/Cloud/cc-sessions$entry_cwd/sessions.json"
            if test -f "$saved"
                set -l in_saved (jq -r --arg id "$sid" '[.[].id] | index($id) // empty' "$saved" 2>/dev/null)
                if test -n "$in_saved"
                    set recoverable 1
                end
            end
        end

        if test $recoverable -eq 1
            set kept (math $kept + 1)
            continue
        end

        if test $dry -eq 1
            set pruned (math $pruned + 1)
            continue
        end

        # Archived, never deleted — the record (and any recorded title) survives.
        # Move FIRST, then annotate the archived copy: `mv -n` refuses silently on
        # a basename collision, and stamping beforehand would leave a half-mutated
        # entry sitting in open/ to be re-stamped and re-counted on every prune.
        mkdir -p "$archive"
        set -l dest "$archive/"(basename "$f")
        # BSD mv -n exits 0 while silently refusing, so the -f check is the real
        # test. Report it: an entry that can't be archived would otherwise be
        # missing from both the archived and the kept count.
        if not mv -n "$f" "$dest" 2>/dev/null; or test -f "$f"
            echo (set_color yellow)"  could not archive "(basename "$f")" (name already in archive)"(set_color normal)
            continue
        end
        set pruned (math $pruned + 1)
        set -l tmp "$dest.tmp.$fish_pid"
        if jq '.archived_reason = "unrecoverable"' "$dest" > "$tmp" 2>/dev/null
            mv "$tmp" "$dest"
        else
            rm -f "$tmp"
        end
    end

    if test $dry -eq 1
        echo "Prune (dry run): $pruned of $checked unrecoverable, $kept recoverable"
    else
        echo "Prune: archived $pruned of $checked, kept $kept recoverable"
    end
end

function _ccs_old --description 'List archived (resumed) session entries for current pwd'
    set -l archive (_ccs_archive_dir)
    if not test -d "$archive"
        echo "No archived sessions"
        return 1
    end
    # Case-insensitive, like the scan: some entries recorded Vaults/, others
    # vaults/, and an exact compare hides whichever case you aren't standing in.
    set -l cwd (string lower (pwd))
    # Build epoch-prefixed sortable list, newest first. One jq per entry reading
    # every field at once — and the title comes from the entry only, never from
    # the transcript: grepping one per archived row cost seconds per call.
    set -l rows
    for f in "$archive"/*.json
        test -f "$f"; or continue
        set -l fields (jq -r '[(.cwd // ""), (.started_at // 0), (.session_id // ""), (.archived_reason // "resumed"), ((.title // "") | gsub("[\t\n]"; " "))] | @tsv' "$f" 2>/dev/null)
        test -n "$fields"; or continue
        set -l e (string split \t -- $fields)
        if test (string lower "$e[1]") != "$cwd"
            continue
        end
        set -a rows (printf '%s\t%s\t%s\t%s\t%s' $e[2] $e[3] $f $e[4] "$e[5]")
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
        set -l title (_ccs_truncate "$parts[5]" 58)
        set -l meta "$parts[4] $when"
        if test -n "$title"
            set meta "$title — $parts[4] $when"
        end
        printf '  %s  %s\n' (set_color cyan)"$short_id"(set_color normal) (set_color brblack)"$meta"(set_color normal)
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
    echo "ccs [add|list|rename|autotitle|rm|resume|old|prune|backup|migrate|help]"
    echo "  add <id> [title]    Add a session (also accepts 'claude --resume <id>')"
    echo "  list                List sessions in current directory"
    echo "  rename <id> <title> Rename a session"
    echo "  autotitle [id]      Auto-generate a title using Haiku"
    echo "  remove <id>         Remove a session"
    echo "  resume              Pick and resume a session (fzf)"
    echo "  old                 List archived (previously-resumed) sessions"
    echo "  prune [--dry-run]   Archive crashed entries that can no longer be recovered"
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
        case prune
            _ccs_prune $argv[2..-1]
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
