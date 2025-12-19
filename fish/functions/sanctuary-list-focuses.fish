function sanctuary-list-focuses --description "List areas and projects for fzf selection"
    # Output format: path|display_name|description
    # For use with fzf --delimiter='|' --with-nth=2,3
    set -l akashic "$HOME/TheAkashicRecords"

    # Areas
    if test -d "$akashic/areas"
        for f in "$akashic/areas"/*.md
            if test -f "$f"
                set -l basename_file (basename $f .md)
                set -l display_name (string replace -a '-' ' ' "$basename_file")
                set -l display_name "📂 $display_name"
                # Get first non-header, non-empty line as description
                set -l desc (cat "$f" | string match -rv '^#|^$' | head -n 1 | string trim | string sub -l 60)
                if test -z "$desc"
                    set desc "(no description)"
                end
                echo "areas/$basename_file|$display_name|$desc"
            end
        end
    end

    # Projects
    if test -d "$akashic/projects"
        for f in "$akashic/projects"/*.md
            if test -f "$f"
                set -l basename_file (basename $f .md)
                set -l display_name (string replace -a '-' ' ' "$basename_file")
                set -l display_name "🎯 $display_name"
                # Get first non-header, non-empty line as description
                set -l desc (cat "$f" | string match -rv '^#|^$' | head -n 1 | string trim | string sub -l 60)
                if test -z "$desc"
                    set desc "(no description)"
                end
                echo "projects/$basename_file|$display_name|$desc"
            end
        end
    end
end
