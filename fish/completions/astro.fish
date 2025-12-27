# Completions for astro command

# Get available charts
function __astro_list_charts
    set -l charts_dir ~/.local/share/astro/charts
    if test -d $charts_dir
        for f in $charts_dir/*.json
            basename $f .json
        end
    end
end

# Check if command needs a chart name
function __astro_needs_chart
    set -l cmd (commandline -opc)
    set -l subcmd $cmd[2]
    if contains -- $subcmd show-chart remove-chart now forecast
        if test (count $cmd) -eq 2
            return 0
        end
    end
    return 1
end

# Main subcommands
complete -c astro -f -n '__fish_use_subcommand' -a 'add-chart' -d 'Add natal chart interactively'
complete -c astro -f -n '__fish_use_subcommand' -a 'list-charts' -d 'List all saved charts'
complete -c astro -f -n '__fish_use_subcommand' -a 'show-chart' -d 'Show chart details'
complete -c astro -f -n '__fish_use_subcommand' -a 'remove-chart' -d 'Remove a chart'
complete -c astro -f -n '__fish_use_subcommand' -a 'now' -d 'Show current transits'
complete -c astro -f -n '__fish_use_subcommand' -a 'forecast' -d 'Forecast upcoming transits'
complete -c astro -f -n '__fish_use_subcommand' -a 'clear-cache' -d 'Clear transit cache'
complete -c astro -f -n '__fish_use_subcommand' -a 'config' -d 'Show configuration'

# Chart name completions
complete -c astro -f -n '__astro_needs_chart' -a '(__astro_list_charts)'

# Forecast options
complete -c astro -f -n '__fish_seen_subcommand_from forecast' -s d -l days -d 'Days to forecast'
complete -c astro -f -n '__fish_seen_subcommand_from forecast' -l date -d 'Start date (YYYY-MM-DD)'
complete -c astro -f -n '__fish_seen_subcommand_from forecast' -s a -l all -d 'Include all objects'
complete -c astro -f -n '__fish_seen_subcommand_from forecast' -s o -l orb -d 'Max orb in degrees'
