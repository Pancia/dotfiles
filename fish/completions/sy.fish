complete -c sy -f

# Subcommands
complete -c sy -n "test (count (commandline -opc)) -eq 1" -a "run test" -d "Subcommand"

# Sections (after run or test)
complete -c sy -n "test (count (commandline -opc)) -eq 2" -a "(~/dotfiles/sanctuary/main-claude.fish --completions)"
