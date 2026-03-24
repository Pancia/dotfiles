# AI inbox triage - file links and web content to the right place
function ai_inbox --description 'Triage web links into inbox system'
    # Create timestamped session directory
    set -l timestamp (date +%Y-%m-%d_%H-%M-%S)
    set -l session_dir "$HOME/Cloud/_inbox/_triage/$timestamp"
    mkdir -p $session_dir

    echo ""
    set_color yellow
    echo "======================================================================="
    echo "  INBOX TRIAGE — session: $timestamp"
    echo "======================================================================="
    set_color normal
    echo ""
    echo "Paste your links (one per line, or space-separated)."
    echo "Press Enter on an empty line when done."
    echo ""

    # Read lines until empty line
    set -l raw_file $session_dir/raw.txt
    while read -l -P "> " line
        if test -z "$line"
            break
        end
        echo $line >> $raw_file
    end

    # Check we got something
    if not test -f $raw_file
        set_color red
        echo "No input. Aborting."
        set_color normal
        rm -rf $session_dir
        return 1
    end

    # Extract URLs from raw input (grep for http/https)
    set -l urls (grep -oE 'https?://[^ ]+' $raw_file)

    if test (count $urls) -eq 0
        set_color red
        echo "No URLs found in input. Aborting."
        set_color normal
        rm -rf $session_dir
        return 1
    end

    echo ""
    set_color cyan
    echo "Found "(count $urls)" URL(s). Cleaning..."
    set_color normal

    # Clean tracking params from URLs
    set -l cleaned (python3 ~/dotfiles/bin/inbox-clean-urls $urls)

    # Dedup against existing _INDEX.md files
    set_color cyan
    echo "Checking for duplicates..."
    set_color normal
    set -l new_urls
    set -l dupes 0
    for result in (inbox-dedup $cleaned)
        set -l url (string split \t -- $result)[1]
        set -l dedup_result (string split \t -- $result)[2]
        set -l where (string split \t -- $result)[3]
        if test "$dedup_result" = "FOUND"
            set dupes (math $dupes + 1)
            set_color yellow
            echo "  SKIP (already in $where): $url"
            set_color normal
        else
            set -a new_urls $url
        end
    end

    if test $dupes -gt 0
        echo ""
        set_color yellow
        echo "Skipped $dupes duplicate(s)."
        set_color normal
    end

    if test (count $new_urls) -eq 0
        set_color red
        echo "All URLs already saved. Nothing to triage."
        set_color normal
        return 0
    end

    # Write cleaned, deduped URLs to links.txt
    for url in $new_urls
        echo $url
    end > $session_dir/links.txt

    set -l count (count $new_urls)
    echo ""
    set_color green
    echo "Triaging $count link(s)..."
    set_color normal
    echo ""

    # cd into session dir so Claude operates from there
    cd $session_dir

    my-claude-code-wrapper --process-label ai_inbox.fish \
        --system-prompt (cat ~/private/ai/prompts/inbox.txt | string collect) \
        "Triage these links: @./links.txt" \
        $argv
end
