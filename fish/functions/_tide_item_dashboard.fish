function _tide_item_dashboard
    set -l parts

    # @ = cmds count
    set -l cmds_out (cmds list 2>/dev/null)
    if test -n "$cmds_out"
        set -l cmds_count (string split ' ' -- $cmds_out | count)
        test $cmds_count -gt 0; and set -a parts "@=$cmds_count"
    end

    # P = PLAN-* files
    set -l plan_count (find . -maxdepth 1 -name 'PLAN-*' 2>/dev/null | count)
    test $plan_count -gt 0; and set -a parts "P=$plan_count"

    # ccs = Claude Code sessions
    set -l cc_file (pwd)"/.claude-sessions"
    if test -f "$cc_file"
        set -l cc_count (string match -rv '^\s*$' < "$cc_file" | count)
        test $cc_count -gt 0; and set -a parts "ccs=$cc_count"
    end

    if test (count $parts) -gt 0
        _tide_print_item dashboard (string join ' ' $parts)
    end
end
