# Backup utilities
function bak --description 'Create backup of file'
    if test -e "$argv[1].bak"
        bak "$argv[1].bak"
    end
    cp "$argv[1]" "$argv[1].bak"
end

function sponge --description 'Soak up stdin and write to file after backup'
    set -l tmp (mktemp)
    bak "$argv[1]"; and cat > "$tmp"; and mv "$tmp" "$argv[1]"
end
