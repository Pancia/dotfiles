function bak {
    if [ -e "$1.bak" ]; then bak "$1.bak"; fi
    cp "$1" "$1.bak"
}

function sponge() {
  local tmp="$(mktemp)"
  bak "$1" && cat > "$tmp" && mv "$tmp" "$1"
}
