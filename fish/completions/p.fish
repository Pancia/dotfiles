# Completions for git project jumping (p)

function __p_projects
    fd --type d --hidden --no-ignore --prune --glob '.git' --max-depth 4 \
        (for path in $FZFM_PROJECT_ROOTS; echo -- --search-path; echo -- $path; end) 2>/dev/null \
        | xargs -I{} dirname {}
end

complete -c p -f -a '(__p_projects)' -d 'Jump to git project'
