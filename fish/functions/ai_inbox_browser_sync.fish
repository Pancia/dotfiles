# Triage open browser tabs into inbox system via browser-sync
function ai_inbox_browser_sync --description 'Triage browser tabs into inbox system'
    set -l source ~/AKR/browser-sync/current.md
    if not test -f $source
        set_color red
        echo "No browser sync file at $source"
        set_color normal
        return 1
    end

    # Create timestamped session directory
    set -l timestamp (date +%Y-%m-%d_%H-%M-%S)
    set -l session_dir "$HOME/Cloud/_inbox/_triage/$timestamp"
    mkdir -p $session_dir

    # Extract markdown links, filter junk, preserve context
    # tabs.md gets the full context (titles, group headers)
    # links.txt gets just the URLs
    set -l url_count 0
    set -l urls

    while read -l line
        # Preserve section headers in tabs.md
        if string match -rq '^##' -- $line
            echo $line >> $session_dir/tabs.md
            continue
        end

        # Parse markdown links: [Title](url)
        if not string match -rq '^\- \[.*\]\(.*\)' -- $line
            continue
        end

        set -l url (string match -r '\]\((.*)\)' -- $line)[2]

        # Filter junk URLs
        if string match -rq '^chrome://' -- $url
            continue
        end
        if string match -rq '^chrome-extension://' -- $url
            continue
        end
        if string match -rq '://localhost[:/]' -- $url
            continue
        end
        if string match -rq '://127\.0\.0\.1[:/]' -- $url
            continue
        end

        echo $line >> $session_dir/tabs.md
        set -a urls $url
        set url_count (math $url_count + 1)
    end < $source

    if test $url_count -eq 0
        set_color red
        echo "No URLs found in browser tabs."
        set_color normal
        rm -rf $session_dir
        return 1
    end

    echo ""
    set_color yellow
    echo "======================================================================="
    echo "  BROWSER SYNC TRIAGE — session: $timestamp"
    echo "======================================================================="
    set_color normal
    echo ""
    set_color cyan
    echo "Found $url_count tab(s). Cleaning URLs..."
    set_color normal

    # Clean tracking params
    set urls (python3 ~/dotfiles/bin/inbox-clean-urls $urls)

    # Dedup against existing _INDEX.md files
    set -l triage_urls
    set -l dupes 0
    for result in (inbox-dedup $urls)
        set -l url (string split \t -- $result)[1]
        set -l dedup_result (string split \t -- $result)[2]
        set -l where (string split \t -- $result)[3]
        if test "$dedup_result" = "FOUND"
            set dupes (math $dupes + 1)
            set_color yellow
            echo "  SKIP (already in $where): $url"
            set_color normal
        else
            set -a triage_urls $url
        end
    end

    if test $dupes -gt 0
        echo ""
        set_color yellow
        echo "Skipped $dupes duplicate(s)."
        set_color normal
    end

    if test (count $triage_urls) -eq 0
        set_color red
        echo "All URLs already saved. Nothing to triage."
        set_color normal
        rm -rf $session_dir
        return 0
    end

    # Write cleaned URLs to links.txt
    for url in $triage_urls
        echo $url
    end > $session_dir/links.txt

    # Rebuild tabs.md to only include non-duplicate URLs
    # (keep the version with all tabs — Claude needs context for closure suggestions)

    set -l count (count $triage_urls)
    echo ""
    set_color green
    echo "Triaging $count link(s)..."
    set_color normal
    echo ""

    # Prepopulate context for the AI agent
    printf '# Inbox Folders\n\n' > $session_dir/context.txt
    ls ~/Cloud/_inbox/ >> $session_dir/context.txt 2>/dev/null
    printf '\n# Tags (inbox-tags --all)\n\n' >> $session_dir/context.txt
    inbox-tags --all >> $session_dir/context.txt 2>/dev/null

    cd $session_dir

    my-claude-code-wrapper --process-label ai_inbox_browser_sync \
        --system-prompt (cat ~/private/ai/prompts/inbox-browser-sync.txt | string collect) \
        "Triage these browser tabs: @./tabs.md — New URLs (not already saved): @./links.txt — Inbox context (folders + tags): @./context.txt" \
        $argv
end
