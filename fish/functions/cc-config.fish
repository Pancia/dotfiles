function cc-config --description "Manage Claude Code project skills and agents"
    set -l config_file ~/dotfiles/ai/cc-config.json

    if not test -f $config_file
        echo "cc-config.json not found at $config_file" >&2
        return 1
    end

    set -l cmd $argv[1]
    set -e argv[1]

    switch "$cmd"
        case sync
            _cc_config_sync $config_file $argv
        case init
            _cc_config_init $config_file
        case edit
            _cc_config_edit $config_file
        case show
            _cc_config_show $config_file
        case list
            _cc_config_list $config_file
        case groups
            _cc_config_groups $config_file
        case '*'
            echo "Usage: cc-config <init|edit|show|sync|list|groups> [args...]" >&2
            echo "" >&2
            echo "  init                              Create .cc-config via fzf picker" >&2
            echo "  edit                              Edit .cc-config with reference comments" >&2
            echo "  show                              Show resolved .cc-config for this project" >&2
            echo "  sync [--dry-run] <group|name...>  Symlink skills+agents into .claude/" >&2
            echo "  list                              Show all registered skills and agents" >&2
            echo "  groups                            Show group definitions" >&2
            return 1
    end
end

function _cc_config_edit
    set -l config_file $argv[1]

    # Save original content (or empty)
    set -l original ""
    if test -f .cc-config
        set original (cat .cc-config)
    end

    # Build reference comment block
    set -l ref "// Groups:"
    for g in (jq -r '.groups | keys[]' $config_file)
        set -l desc (jq -r --arg g $g '.groups[$g] | if type == "string" then .
            elif type == "object" then [to_entries[] | "\(.key): \(.value | if type == "array" then join(", ") else . end)"] | join("  |  ")
            elif type == "array" then join(", ")
            else . end' $config_file)
        set -a ref (printf "//   %-16s %s" $g $desc)
    end
    set -a ref "//"
    set -a ref "// Skills:"
    for entry in (_cc_config_resolve_registry $config_file skills)
        set -l name (string split \t $entry)[1]
        set -a ref (printf "//   %s" $name)
    end
    set -a ref "//"
    set -a ref "// Agents:"
    for entry in (_cc_config_resolve_registry $config_file agents)
        set -l name (string split \t $entry)[1]
        set -a ref (printf "//   %s" $name)
    end
    set -a ref "//"
    set -a ref "// Commands:"
    for entry in (_cc_config_resolve_registry $config_file commands)
        set -l name (string split \t $entry)[1]
        set -a ref (printf "//   %s" $name)
    end

    # Write file with vim modeline, syntax hint, content, and reference block
    begin
        echo "// vim: set ft=c:"
        echo "// One item per line. Groups (#name), skills, agents, or commands."
        printf '%s\n' $original
        echo ""
        printf '%s\n' $ref
    end > .cc-config

    # Open in editor
    set -l editor $EDITOR
    if test -z "$editor"
        set editor vi
    end
    $editor .cc-config

    # Strip // lines and blank lines, keep everything else
    set -l content (string match -v '//*' < .cc-config | string match -v -r '^\s*$')

    if test (count $content) -eq 0
        echo "Empty config, removing .cc-config" >&2
        rm .cc-config
        return
    end

    # Validate: one item per line
    set -l valid 1
    for line in $content
        if string match -q '* *' $line
            echo "Warning: multiple items on one line: '$line'" >&2
            set valid 0
        end
    end

    printf '%s\n' $content > .cc-config

    if test $valid -eq 0
        echo "Put each group/skill/agent/command on its own line." >&2
        return 1
    end

    echo "Updated .cc-config: "(string join ', ' $content)
    _cc_config_sync $config_file $content
end

function _cc_config_show
    set -l config_file $argv[1]

    if not test -f .cc-config
        echo "No .cc-config in current directory." >&2
        return 1
    end

    set -l profile (string match -v '//*' < .cc-config | string match -v -r '^\s*$')
    echo "Profile: $profile"
    echo ""

    set -g _CC_GROUP_NAMES (jq -r '.groups | keys[]' $config_file)

    for section in skills agents commands
        set -l names
        for target in $profile
            set -l resolved (_cc_config_resolve_group $config_file $section $target)
            for name in $resolved
                if not contains $name $names
                    set -a names $name
                end
            end
        end
        if test (count $names) -gt 0
            printf "  %d %s: %s\n" (count $names) $section (string join ', ' $names)
        end
    end

    set -e _CC_GROUP_NAMES
end

function _cc_config_init
    set -l config_file $argv[1]

    if test -f .cc-config
        set -l current (string trim (cat .cc-config))
        read -P ".cc-config already exists ($current). Overwrite? [y/N] " -l confirm
        if test "$confirm" != y -a "$confirm" != Y
            return 1
        end
    end

    # Build fzf input: groups first, then skills, then agents
    set -l choices
    for g in (jq -r '.groups | keys[]' $config_file)
        set -a choices (printf "%-24s (group)" $g)
    end
    for entry in (_cc_config_resolve_registry $config_file skills)
        set -l name (string split \t $entry)[1]
        set -a choices (printf "%-24s (skill)" $name)
    end
    for entry in (_cc_config_resolve_registry $config_file agents)
        set -l name (string split \t $entry)[1]
        set -a choices (printf "%-24s (agent)" $name)
    end
    for entry in (_cc_config_resolve_registry $config_file commands)
        set -l name (string split \t $entry)[1]
        set -a choices (printf "%-24s (command)" $name)
    end

    set -l selected (printf '%s\n' $choices | fzf --multi --header "Select groups, skills, and/or agents (TAB to multi-select)")
    if test -z "$selected"
        echo "No selection made." >&2
        return 1
    end

    # Extract just the names (first field)
    set -l names
    for line in $selected
        set -a names (string trim (string split '(' $line)[1])
    end

    printf '%s\n' $names > .cc-config
    echo "Created .cc-config: $names"
    _cc_config_sync $config_file $names
end

# Resolve a registry section ("skills" or "agents") to name→path pairs
# For skills: globs look for SKILL.md in subdirs
# For agents: globs look for *.md files directly
function _cc_config_resolve_registry
    set -l config_file $argv[1]
    set -l section $argv[2] # "skills" or "agents"

    set -l raw (jq -r --arg s $section '.[$s] // {} | to_entries[] | "\(.key)\t\(.value)"' $config_file)
    for entry in $raw
        set -l name (string split \t $entry)[1]
        set -l path (string split \t $entry)[2]
        set path (string replace '~' $HOME $path)

        if string match -q '*/*' $path; and string match -q '\*' (string sub -s -1 $path)
            # Directory glob
            set -l base_dir (string replace '/*' '' $path)
            if test -d $base_dir
                if test "$section" = skills
                    for item_dir in $base_dir/*/
                        set -l item_name (basename $item_dir)
                        if test -f $item_dir/SKILL.md
                            echo $item_name\t(string trim -r -c '/' $item_dir)
                        end
                    end
                else
                    # agents and commands are both .md files
                    for item_file in $base_dir/*.md
                        set -l item_name (basename $item_file .md)
                        echo $item_name\t$item_file
                    end
                end
            else
                echo "Warning: glob directory not found: $base_dir" >&2
            end
        else
            echo $name\t$path
        end
    end
end

# Recursively resolve a group to names for a given section
# argv: config_file section group_name [visited...]
# Uses _CC_GROUP_NAMES (set by caller) to avoid jq per-member
function _cc_config_resolve_group
    set -l config_file $argv[1]
    set -l section $argv[2]
    set -l group_name $argv[3]
    set -l visited $argv[4..]

    if contains $group_name $visited
        return
    end
    set -a visited $group_name

    # Not a group — treat as literal name
    if not contains $group_name $_CC_GROUP_NAMES
        echo $group_name
        return
    end

    # Wildcard group
    set -l group_value (jq -r --arg g $group_name '.groups[$g] // empty' $config_file)
    if test "$group_value" = '*'
        _cc_config_resolve_registry $config_file $section | while read line
            echo (string split \t $line)[1]
        end
        return
    end

    # Get members for this section from group object or array
    set -l members (jq -r --arg g $group_name --arg s $section \
        '.groups[$g] | if type == "object" then .[$s][]? // empty elif type == "array" then .[]? // empty else empty end' \
        $config_file)

    for member in $members
        if contains $member $_CC_GROUP_NAMES; and not contains $member $visited
            _cc_config_resolve_group $config_file $section $member $visited
        else
            echo $member
        end
    end
end

function _cc_config_sync
    set -l config_file $argv[1]
    set -e argv[1]

    set -l dry_run 0
    set -l targets

    for arg in $argv
        if test "$arg" = --dry-run
            set dry_run 1
        else
            set -a targets $arg
        end
    end

    if test (count $targets) -eq 0
        echo "Usage: cc-config sync [--dry-run] <group|name...>" >&2
        return 1
    end

    # Sync both skills and agents
    for section in skills agents commands
        _cc_config_sync_section $config_file $section $dry_run $targets
    end
end

function _cc_config_sync_section
    set -l config_file $argv[1]
    set -l section $argv[2]
    set -l dry_run $argv[3]
    set -l targets $argv[4..]

    # Precompute group names once (avoids jq per-member in recursive resolution)
    set -g _CC_GROUP_NAMES (jq -r '.groups | keys[]' $config_file)

    # Resolve targets to names (deduplicated)
    set -l item_names
    for target in $targets
        set -l resolved (_cc_config_resolve_group $config_file $section $target)
        for name in $resolved
            if not contains $name $item_names
                set -a item_names $name
            end
        end
    end

    # Nothing to sync for this section
    if test (count $item_names) -eq 0
        return
    end

    # Build registry map
    set -l reg_names
    set -l reg_paths
    set -l registry (_cc_config_resolve_registry $config_file $section)
    for entry in $registry
        set -l parts (string split \t $entry)
        set -a reg_names $parts[1]
        set -a reg_paths $parts[2]
    end

    # Resolve names to paths
    set -l link_names
    set -l link_paths
    for name in $item_names
        set -l idx 0
        set -l found 0
        for rn in $reg_names
            set idx (math $idx + 1)
            if test "$rn" = "$name"
                set -l path $reg_paths[$idx]
                # Skills are dirs; agents and commands are files
                if test "$section" = skills; and not test -d $path
                    echo "Warning: $section '$name' path not found: $path" >&2
                else if test "$section" != skills; and not test -f $path
                    echo "Warning: $section '$name' path not found: $path" >&2
                else
                    set -a link_names $name
                    set -a link_paths $path
                    set found 1
                end
                break
            end
        end
        if test $found -eq 0
            echo "Warning: $section '$name' not found in registry" >&2
        end
    end

    if test (count $link_names) -eq 0
        return
    end

    set -l target_dir .claude/$section

    if test $dry_run -eq 1
        echo "Would sync "(count $link_names)" $section into $target_dir:"
        for i in (seq (count $link_names))
            echo "  $link_names[$i] -> $link_paths[$i]"
        end
        return 0
    end

    # Wipe and relink
    mkdir -p $target_dir
    for f in $target_dir/*
        if test -L $f
            rm $f
        end
    end

    set -l linked 0
    for i in (seq (count $link_names))
        set -l symlink_name $link_names[$i]
        # Agent and command symlinks need .md extension
        if test "$section" != skills
            set symlink_name $symlink_name.md
        end
        ln -s $link_paths[$i] $target_dir/$symlink_name
        set linked (math $linked + 1)
    end

    echo "Synced $linked $section into $target_dir"
    set -e _CC_GROUP_NAMES
end

function _cc_config_list
    set -l config_file $argv[1]

    for section in skills agents commands
        set -l registry (_cc_config_resolve_registry $config_file $section)
        if test (count $registry) -eq 0
            continue
        end
        echo "Registered $section:"
        for entry in $registry
            set -l parts (string split \t $entry)
            set -l marker "  "
            set -l check_name $parts[1]
            if test "$section" != skills
                set check_name $check_name.md
            end
            if test -L .claude/$section/$check_name
                set marker "* "
            end
            printf "  %s%-24s %s\n" $marker $parts[1] $parts[2]
        end
        echo ""
    end
end

function _cc_config_groups
    set -l config_file $argv[1]
    set -l group_names (jq -r '.groups | keys[]' $config_file)

    echo "Groups:"
    for g in $group_names
        set -l desc (jq -r --arg g $g '.groups[$g] | if type == "string" then .
            elif type == "object" then [to_entries[] | "\(.key): \(.value | if type == "array" then join(", ") else . end)"] | join("  |  ")
            elif type == "array" then join(", ")
            else . end' $config_file)
        printf "  %-16s %s\n" $g $desc
    end
end
