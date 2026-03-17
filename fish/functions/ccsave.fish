function ccsave --description 'Save current claude session with auto-generated title'
    set -l id $argv[1]
    if test -z "$id"
        echo "Usage: ccsave <id>"
        echo "  Adds the session and auto-generates a title using Haiku"
        return 1
    end

    # Add session first (no title)
    ccs add "$id"

    # Then autotitle it
    ccs autotitle "$id"
end
