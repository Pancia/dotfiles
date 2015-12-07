function rm {
local dir prefix timestamp
dir="$(pwd)"
timestamp="$(date '+%Y-%m-%d_%X')"
prefix="${dir//\//%}T${timestamp}<->"
for i in "$@"; do
    command mv "$i" "~/.Trash/${prefix}${i//\//%}"
done
}
