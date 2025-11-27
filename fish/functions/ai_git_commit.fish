function ai_git_commit --description 'Commit with AI-generated message'
    set -l message (git diff --staged | ai_write_git_commit | string collect)
    git commit --edit -m $message
end
