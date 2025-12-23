function sanctuary-build-context --description "Aggregate context from TheAkashicRecords for Claude"
    set -l akashic "$HOME/TheAkashicRecords"

    # Vision (full content)
    if test -f "$akashic/vision.md"
        echo "## Vision"
        echo
        cat "$akashic/vision.md"
        echo
    end

    # NOW (full content)
    if test -f "$akashic/NOW.md"
        echo "## Current Focus (NOW)"
        echo
        cat "$akashic/NOW.md"
        echo
    end

    # Document outlines (headers only)
    echo "## Document Outlines"
    echo
    for file in $akashic/*.md
        set -l basename (path basename $file)
        # Skip files we already included in full
        if test "$basename" = "vision.md" -o "$basename" = "NOW.md"
            continue
        end
        set -l headers (grep -E '^#{1,4} ' $file 2>/dev/null)
        if test -n "$headers"
            echo "### $basename"
            echo "$headers"
            echo
        end
    end

    # Areas outlines
    if test -d "$akashic/areas"
        echo "## Areas"
        echo
        for file in $akashic/areas/*.md
            test -f $file; or continue
            set -l basename (path basename $file)
            set -l headers (grep -E '^#{1,4} ' $file 2>/dev/null)
            if test -n "$headers"
                echo "### $basename"
                echo "$headers"
                echo
            end
        end
    end

    # Projects outlines
    if test -d "$akashic/projects"
        echo "## Projects"
        echo
        for file in $akashic/projects/*.md
            test -f $file; or continue
            set -l basename (path basename $file)
            set -l headers (grep -E '^#{1,4} ' $file 2>/dev/null)
            if test -n "$headers"
                echo "### $basename"
                echo "$headers"
                echo
            end
        end
    end
end
