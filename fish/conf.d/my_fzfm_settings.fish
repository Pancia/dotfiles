# Change ctrl-j to alt-j to avoid conflict with newline character
set -gx fzfm_key_jump_frecent 'alt-j'

set -gx fzfm_list_cmd_jump_main fd --follow --max-depth 5 --no-ignore-vcs --type d (for path in $FZFM_MAIN_ROOT_JUMP; echo -- --search-path; echo -- $path; end)

set -gx fzfm_list_cmd_jump_frecent "cat \
    (echo -- $FZFM_MAIN_ROOT_JUMP | psub) \
    ($fzfm_list_cmd_jump_main | string trim --right --chars '/' | psub) \
    (fd --max-depth 1 --type d --no-ignore --search-path /Volumes | string trim --right --chars '/' | psub) \
    (fd --max-depth 1 --type d --no-ignore --search-path $HOME | string trim --right --chars '/' | psub) \
    (fre --sorted --store_name dir_$FZFM_FRE_STORE | __fzfm_filter_existing | psub) \
    | __fzfm_dedup"

set -gx fzfm_list_cmd_jump_frecent_aux "cat \
    (echo -- $FZFM_MAIN_ROOT_JUMP | psub) \
    (fre --sorted --store_name dir_$FZFM_FRE_STORE | __fzfm_filter_existing | psub) \
    (fre --sorted --store_name dir_$FZFM_FRE_STORE_AUX | __fzfm_filter_existing | psub) \
    ($fzfm_list_cmd_jump_main | psub) \
    (fd --max-depth 1 --type d --no-ignore --search-path /Volumes | psub) \
    (fd --max-depth 1 --type d --no-ignore --search-path $HOME | psub) \
    | __fzfm_dedup"

# Git project jumping - searches for .git directories in FZFM_PROJECT_ROOTS
set -gx FZFM_PROJECT_ROOTS $HOME/projects $HOME/AndroidStudioProjects $HOME/private/ $HOME/ProtonDrive/

set -gx fzfm_list_cmd_jump_projects "fd --type d --hidden --no-ignore --prune --glob '.git' --max-depth 4 \
    (for path in \$FZFM_PROJECT_ROOTS; echo -- --search-path; echo -- \$path; end) \
    | xargs -I{} dirname {} | __fzfm_dedup"
