# Completions for cjson command

# Main subcommands
complete -c cjson -f -n '__fish_use_subcommand' -a 'encode' -d 'JSON → CJSON'
complete -c cjson -f -n '__fish_use_subcommand' -a 'decode' -d 'CJSON → JSON'
complete -c cjson -f -n '__fish_use_subcommand' -a 'stats' -d 'Show compression stats'

# Common options for encode/decode
complete -c cjson -n '__fish_seen_subcommand_from encode decode' -s o -l output -r -d 'Output file'
complete -c cjson -n '__fish_seen_subcommand_from encode decode' -l pretty -d 'Pretty-print output'

# Encode-specific options
complete -c cjson -n '__fish_seen_subcommand_from encode' -l min-freq -r -d 'Min occurrences to alias (default: 2)'

# File argument completion (JSON files)
complete -c cjson -n '__fish_seen_subcommand_from encode decode stats' -F -k -a '*.json'
