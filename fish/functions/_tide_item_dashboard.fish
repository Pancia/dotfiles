function _tide_item_dashboard
    set -l parts (dashboard-parts)
    if test (count $parts) -gt 0
        _tide_print_item dashboard (string join ' ' $parts)
    end
end
