#!/usr/bin/env fish

set -g script_dir (dirname (status filename))
set -g akashic "$HOME/TheAkashicRecords"
set -g state_dir "$HOME/.local/state/sanctuary"
set -g main_md "$akashic/_main.md"

# Ensure state directory exists
mkdir -p "$state_dir"

# =============================================================================
# Global State Variables (shared between functions)
# =============================================================================
set -g g_mood ""
set -g g_focus_path ""
set -g g_focus_name ""
set -g g_intention ""
set -g g_journal_template ""

# =============================================================================
# Section Definitions (used for completions and dispatch)
# =============================================================================
set -g sanctuary_sections \
    vision \
    calendar \
    mood \
    inbox \
    intention \
    focus \
    template \
    state \
    journal \
    edit \
    pomodoro

# Handle --completions flag
if test "$argv[1]" = "--completions"
    printf '%s\n' $sanctuary_sections
    exit 0
end

# =============================================================================
# Subcommand Parsing: run <section> | test <section>
# =============================================================================
set -g test_mode 0
set -g target_section ""

if test (count $argv) -gt 0
    switch $argv[1]
        case run
            set test_mode 0
            set target_section $argv[2]
        case test
            set test_mode 1
            set target_section $argv[2]
        case '*'
            echo "Usage: sanctuary [run|test] <section>"
            echo "       sanctuary  # run full flow"
            exit 1
    end
end

# =============================================================================
# Section vision: Display Vision
# =============================================================================
function _sanctuary_vision
    echo
    set_color --bold cyan
    echo "═══════════════════════════════════════════════════════════════════════════"
    echo "                              SANCTUARY"
    echo "═══════════════════════════════════════════════════════════════════════════"
    set_color normal
    echo

    if test -f "$akashic/vision.md"
        set_color yellow
        echo "YOUR VISION:"
        set_color normal
        cat "$akashic/vision.md"
        echo
    end
end

# =============================================================================
# Section calendar: Display Calendar (24 hours)
# =============================================================================
function _sanctuary_calendar
    echo "───────────────────────────────────────────────────────────────────────────"
    echo
    set_color yellow
    echo "UPCOMING (next 24 hours):"
    set_color normal
    swift "$script_dir/calendar.swift" 24 2>/dev/null
    echo

    set_color --dim
    echo "Today is "(date +"%A, %B %d, %Y")" at "(date +"%H:%M")
    set_color normal
    echo
end

# =============================================================================
# Section focus: fzf Selection of Area/Project
# =============================================================================
function _sanctuary_focus
    set_color --bold
    echo "Choose your focus:"
    set_color normal

    set -l focus_selection (sanctuary-list-focuses | fzf \
        --delimiter='|' \
        --with-nth=2,3 \
        --preview="cat '$akashic/{1}.md' 2>/dev/null || echo 'No preview available'" \
        --preview-window=right:50%:wrap \
        --height=50% \
        --prompt="Focus > ")

    if test -z "$focus_selection"
        set_color red
        echo "No focus selected. Exiting."
        set_color normal
        exit 1
    end

    set -g g_focus_path (echo $focus_selection | cut -d'|' -f1)
    set -g g_focus_name (echo $focus_selection | cut -d'|' -f2 | string trim)

    echo
    set_color green
    echo "Focus: $g_focus_name"
    set_color normal
    echo
end

# =============================================================================
# Section mood: Prompt for Mood
# =============================================================================
function _sanctuary_mood
    echo "───────────────────────────────────────────────────────────────────────────"
    echo
    set_color --bold
    echo "How are you feeling right now?"
    set_color --dim
    echo "(energy level, emotions, physical state - be honest)"
    set_color normal

    read -P "> " g_mood
    or exit 0

    if test -z "$g_mood"
        set -g g_mood "neutral"
    end

    echo
end

# =============================================================================
# Section inbox: Display Inbox Journals
# =============================================================================
function _sanctuary_inbox
    set -l journal_files (find /Users/anthony/Cloud/_inbox/Journals -type f \( -name "*.md" -o -name "*.txt" \) 2>/dev/null)
    if test (count $journal_files) -gt 0
        echo "───────────────────────────────────────────────────────────────────────────"
        echo
        set_color yellow
        echo "INBOX JOURNALS:"
        set_color normal
        bat --paging=never --style=plain $journal_files
        echo
    end
end

# =============================================================================
# Section intention: Claude Intention-Setting
# =============================================================================
function _sanctuary_intention
    set_color --bold cyan
    echo "Setting your intention with Claude..."
    set_color normal
    echo

    # Build context
    set -l context (sanctuary-build-context)

    # Read system prompt
    set -l system_prompt (cat "$script_dir/prompts/session-start.md")

    # Build user prompt with context
    set -l current_time (date +"%H:%M on %A")
    set -l user_prompt "## Context

$context

## Current State

**Mood:** $g_mood
**Focus:** $g_focus_name ($g_focus_path)
**Time:** $current_time

---

Help me set a clear intention for this session. Start by acknowledging how I'm feeling, then help me arrive at a specific, achievable intention for my work on $g_focus_name."

    # Interactive Claude session for intention-setting
    claude --system-prompt "$system_prompt" "$user_prompt"

    echo
    set_color --bold
    echo "What's your intention for this session?"
    set_color --dim
    echo "(Type the intention you arrived at)"
    set_color normal
    read -P "> " g_intention
    or exit 0

    if test -z "$g_intention"
        set -g g_intention "Work mindfully on $g_focus_name"
    end

    echo
end

# =============================================================================
# Section template: Claude Generates Dynamic Journal Template
# =============================================================================
function _sanctuary_template
    set_color --bold cyan
    echo "Generating your journal template..."
    set_color normal

    set -l template_prompt (cat "$script_dir/prompts/journal-template.md")
    set -l hour (date +"%H")
    set -l time_of_day "morning"
    if test $hour -ge 12 -a $hour -lt 17
        set time_of_day "afternoon"
    else if test $hour -ge 17
        set time_of_day "evening"
    end

    set -l template_request "Generate a journal template for:
- **Mood:** $g_mood
- **Focus:** $g_focus_name
- **Intention:** $g_intention
- **Time of day:** $time_of_day

Output ONLY the markdown template, nothing else."

    set -g g_journal_template (echo "$template_request" | claude -p --system-prompt "$template_prompt" 2>/dev/null | string collect)

    # Fallback if Claude fails
    if test -z "$g_journal_template"
        set -g g_journal_template "## Settling in

### How is my body feeling right now?

### What's my intention for this session?

### What am I grateful for?

<INSERT>

---"
        echo
        set_color yellow
        echo "(Using default template)"
        set_color normal
    else
        echo
        set_color green
        echo "Template generated:"
        set_color normal
        echo
        echo "$g_journal_template"
    end
end

# =============================================================================
# Section state: Create Session State File (JSON)
# =============================================================================
function _sanctuary_state --argument-names test_mode
    set -l session_id (date -u +"%Y-%m-%dT%H:%M:%S")
    set -l session_file "$state_dir/current-session.json"

    if test "$test_mode" = "1"
        set_color yellow
        echo "[TEST MODE] Would write session state to: $session_file"
        echo "[TEST MODE] Session ID: $session_id"
        echo "[TEST MODE] Focus: $g_focus_path ($g_focus_name)"
        echo "[TEST MODE] Mood: $g_mood"
        echo "[TEST MODE] Intention: $g_intention"
        set_color normal
    else
        # Write session state as JSON using jq for proper escaping
        echo '{}' | jq \
            --arg session_id "$session_id" \
            --arg focus "$g_focus_path" \
            --arg focus_name "$g_focus_name" \
            --arg mood "$g_mood" \
            --arg intention "$g_intention" \
            '{
                session_id: $session_id,
                focus: $focus,
                focus_name: $focus_name,
                mood: $mood,
                intention: $intention,
                work_sessions_completed: 0,
                started_at: $session_id
            }' > "$session_file"
    end
end

# =============================================================================
# Section journal: Create Journal Entry with Template
# =============================================================================
function _sanctuary_journal --argument-names test_mode
    if test "$test_mode" = "1"
        set_color yellow
        echo "[TEST MODE] Would create journal entry at: $main_md"
        echo "[TEST MODE] Would prepend session header with:"
        echo "[TEST MODE]   Focus: $g_focus_name"
        echo "[TEST MODE]   Intention: $g_intention"
        echo "[TEST MODE]   Template: (journal template)"
        set_color normal
    else
        set -l temp_file (mktemp)

        echo "# Session - "(date +%Y-%m-%d_%H:%M:%S) > $temp_file
        echo "**Focus:** $g_focus_name" >> $temp_file
        echo "**Intention:** $g_intention" >> $temp_file
        echo >> $temp_file
        echo "$g_journal_template" >> $temp_file

        if test -f "$main_md"
            cat "$main_md" >> $temp_file
        end

        mv $temp_file "$main_md"
    end
end

# =============================================================================
# Section edit: Open Neovim at <INSERT>
# =============================================================================
function _sanctuary_edit
    set_color --bold green
    echo "Opening journal... Begin your session."
    set_color normal
    sleep 1

    nvim '+/<INSERT>' '+normal cc' '+startinsert' "$main_md"
end

# =============================================================================
# Section pomodoro: Configure Pymodoro Session
# =============================================================================

function _sanctuary_pomodoro --argument-names test_mode
    # TUI config dialog
    set -l config (uv run "$script_dir/pomo_config.py")
    if test -z "$config"
        return
    end

    # Parse values
    set -l parts (string split '/' $config)
    set -l work $parts[1]
    set -l short $parts[2]
    set -l sessions $parts[3]

    # Select label from history, areas, and projects
    set -l label_choices (begin
        # Recent labels from pymodoro log (unique, most recent first)
        if test -f ~/.log/pymodoro.log
            sed -n 's/.*: "\(.*\)"/\1/p' ~/.log/pymodoro.log | tail -r | awk '!seen[$0]++'
        end
        # Areas and projects
        sanctuary-list-focuses | cut -d'|' -f2 | string replace -r '^[^ ]+ ' ''
    end)

    set -l LABEL (printf '%s\n' $label_choices | fzf --prompt="Label > " --print-query | tail -1)

    # In test mode, show command but don't launch
    if test "$test_mode" = "1"
        set_color yellow
        if test -n "$LABEL"
            echo "[TEST MODE] Would launch: pymodoro --label \"$LABEL\" --work $work --short $short --long $work --max-sessions $sessions --notify 0 --confirm"
        else
            echo "[TEST MODE] No label selected. Would prompt to start pymodoro anyway."
        end
        set_color normal
        return
    end

    set -l pomo_cmd "pymodoro --work $work --short $short --long $work --max-sessions $sessions --notify 0 --confirm"
    if test -n "$LABEL"
        set pomo_cmd "$pomo_cmd --label \"$LABEL\""
    else
        read -P "No label selected. Start pymodoro anyway? [y/N] " confirm
        if test "$confirm" != "y" -a "$confirm" != "Y"
            return
        end
    end

    # Launch in a Kitty split pane
    kitty @ launch --location=vsplit --hold --cwd=current fish -c "$pomo_cmd"
end

# =============================================================================
# Section Dispatch Function
# =============================================================================
function _sanctuary_run_section --argument-names section test_mode
    switch $section
        case vision
            _sanctuary_vision
        case calendar
            _sanctuary_calendar
        case mood
            _sanctuary_mood
        case inbox
            _sanctuary_inbox
        case intention
            _sanctuary_intention
        case focus
            _sanctuary_focus
        case template
            _sanctuary_template
        case state
            _sanctuary_state $test_mode
        case journal
            _sanctuary_journal $test_mode
        case edit
            _sanctuary_edit
        case pomodoro
            _sanctuary_pomodoro $test_mode
        case '*'
            echo "Unknown section: $section"
            echo "Valid: vision, calendar, mood, inbox, intention, focus, template, state, journal, edit, pomodoro"
            return 1
    end
end

# =============================================================================
# Main Execution
# =============================================================================

# If section specified, run only that section
if test -n "$target_section"
    _sanctuary_run_section $target_section $test_mode
    exit $status
end

# Default: run all sections in order
_sanctuary_vision
_sanctuary_calendar
_sanctuary_mood
_sanctuary_inbox
_sanctuary_intention
_sanctuary_focus
_sanctuary_template
_sanctuary_state 0
_sanctuary_journal 0
_sanctuary_edit
_sanctuary_pomodoro 0

# Return to interactive shell when done
cd $script_dir
exec fish
