function sanctuary-build-context --description "Aggregate context from TheAkashicRecords for sanctuary's claude intention setter"
    set -l akashic "$HOME/TheAkashicRecords"
    set -l sanctuary_dir (dirname (status dirname))"/sanctuary"

    # Vision
    if test -f "$akashic/vision.md"
        echo "## Vision"
        echo
        cat "$akashic/vision.md"
        echo
    end

    # Anchors
    if test -f "$akashic/anchors.md"
        echo "## Anchors"
        echo
        cat "$akashic/anchors.md"
        echo
    end

    # NOW (current tasks)
    if test -f "$akashic/NOW.md"
        echo "## Current Focus (NOW)"
        echo
        cat "$akashic/NOW.md"
        echo
    end

    # TASKS
    if test -f "$akashic/tasks.md"
        echo "## Task list"
        echo
        cat "$akashic/tasks.md"
        echo
    end

    # Areas
    if test -d "$akashic/areas"
        set -l area_files (find "$akashic/areas" -name "*.md" -type f 2>/dev/null)
        if test (count $area_files) -gt 0
            echo "## Areas"
            echo
            for f in $area_files
                set -l name (basename $f .md | string replace -a '-' ' ')
                echo "### $name"
                # First 5 lines as description
                head -n 5 "$f" | string match -rv '^#' | string trim
                echo
            end
        end
    end

    # Projects
    if test -d "$akashic/projects"
        set -l project_files (find "$akashic/projects" -name "*.md" -type f 2>/dev/null)
        if test (count $project_files) -gt 0
            echo "## Projects"
            echo
            for f in $project_files
                set -l name (basename $f .md | string replace -a '-' ' ')
                echo "### $name"
                # First 5 lines as description
                head -n 5 "$f" | string match -rv '^#' | string trim
                echo
            end
        end
    end

    # Calendar (next 24 hours)
    echo "## Calendar (next 24 hours)"
    echo
    swift "$HOME/dotfiles/sanctuary/calendar.swift" 24 2>/dev/null
    echo
end
