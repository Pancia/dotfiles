function _tide_item_dashboard
    set -l parts

    # Pending CLAUDE.md updates
    set -l pending_files .cc/pending-updates-*.md
    if test -e "$pending_files[1]"
        set -a parts "✎"
    end

    # @ = cmds count
    set -l cmds_out (cmds list 2>/dev/null)
    if test -n "$cmds_out"
        set -l cmds_count (string split ' ' -- $cmds_out | count)
        test $cmds_count -gt 0; and set -a parts "@"
    end

    # P = PLAN-* files in .cc/
    set -l plan_count (find .cc -maxdepth 1 -name 'PLAN-*' 2>/dev/null | count)
    test $plan_count -gt 0; and set -a parts "P"

    # Claude Code sessions to resume
    set -l cc_file (pwd)"/.cc/sessions.json"
    if test -f "$cc_file"
        set -l cc_count (jq 'length' "$cc_file" 2>/dev/null)
        test -n "$cc_count" -a "$cc_count" -gt 0; and set -a parts "⎈"
    end

    if test (count $parts) -gt 0
        _tide_print_item dashboard (string join ' ' $parts)
    end
end
