function sanctuary-build-context --description "Aggregate context from TheAkashicRecords for Claude"
    set -l akashic "$HOME/TheAkashicRecords"
    set -l sanctuary_dir (dirname (status dirname))"/sanctuary"

    # Vision
    if test -f "$akashic/vision.md"
        echo "## Vision"
        echo
        cat "$akashic/vision.md"
        echo
    end

    # NOW (current tasks)
    if test -f "$akashic/NOW.md"
        echo "## Current Focus (NOW)"
        echo
        cat "$akashic/NOW.md"
        echo
    end
end
