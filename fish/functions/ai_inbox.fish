# AI inbox triage - file links and web content to the right place
function ai_inbox --description 'Triage web links into inbox system'
    # Get valid ytdl types from the ytdl script
    set -l ytdl_types (grep '^set -g YTDL_VALID_TYPES' ~/dotfiles/bin/ytdl | string replace -r '.*YTDL_VALID_TYPES ' '' | string split ' ')

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
    set_color brblue
    echo "YouTube: prefix with a type to download via ytdl:"
    printf '  %s\n' $ytdl_types
    echo "  (YouTube URLs without a prefix will prompt for type)"
    set_color normal
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

    # Parse input: separate type-annotated lines from plain URLs
    set -l yt_urls
    set -l yt_types
    set -l plain_urls

    while read -l line
        set -l first_word (string split ' ' -- $line)[1]
        if contains -- $first_word $ytdl_types
            # Type-annotated line: extract URLs after the keyword
            set -l rest (string replace -r '^\S+\s+' '' -- $line)
            for url in (printf '%s' "$rest" | grep -oE 'https?://[^ ]+')
                set -a yt_urls $url
                set -a yt_types $first_word
            end
        else
            for url in (printf '%s' "$line" | grep -oE 'https?://[^ ]+')
                set -a plain_urls $url
            end
        end
    end < $raw_file

    if test (count $yt_urls) -eq 0 -a (count $plain_urls) -eq 0
        set_color red
        echo "No URLs found in input. Aborting."
        set_color normal
        rm -rf $session_dir
        return 1
    end

    echo ""
    set_color cyan
    echo "Found "(math (count $yt_urls) + (count $plain_urls))" URL(s). Cleaning..."
    set_color normal

    # Clean tracking params from all URLs
    if test (count $yt_urls) -gt 0
        set yt_urls (python3 ~/dotfiles/bin/inbox-clean-urls $yt_urls)
    end
    if test (count $plain_urls) -gt 0
        set plain_urls (python3 ~/dotfiles/bin/inbox-clean-urls $plain_urls)
    end

    # Dedup plain URLs against existing _INDEX.md files
    set -l triage_urls
    if test (count $plain_urls) -gt 0
        set_color cyan
        echo "Checking for duplicates..."
        set_color normal
        set -l dupes 0
        for result in (inbox-dedup $plain_urls)
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
    end

    # Download YouTube URLs via ytdl
    if test (count $yt_urls) -gt 0
        echo ""
        set_color green
        echo "Downloading "(count $yt_urls)" YouTube video(s)..."
        set_color normal
        for i in (seq (count $yt_urls))
            echo ""
            set_color cyan
            echo "[$i/"(count $yt_urls)"] ytdl $yt_types[$i] $yt_urls[$i]"
            set_color normal
            ytdl $yt_types[$i] $yt_urls[$i]
        end
    end

    # Triage remaining non-YouTube URLs via Claude
    if test (count $triage_urls) -eq 0
        if test (count $yt_urls) -gt 0
            echo ""
            set_color green
            echo "All done! No non-YouTube URLs to triage."
            set_color normal
        else
            set_color red
            echo "All URLs already saved. Nothing to triage."
            set_color normal
        end
        rm -rf $session_dir
        return 0
    end

    # Write triage URLs to links.txt
    for url in $triage_urls
        echo $url
    end > $session_dir/links.txt

    set -l count (count $triage_urls)
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
