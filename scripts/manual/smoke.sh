#! /usr/bin/env nix-shell
#! nix-shell -i bash -p wtype jq grim
# Spec: WIN-1, WIN-3, WIN-4, CONF-3.
# Run from the repo root after `nix build`, with no Anchorage windows open. Uses a temp
# XDG_CONFIG_HOME and XDG_STATE_HOME. Screenshots go to $OUT.
cd "$(dirname "$0")/../.." || exit 1
. scripts/manual/lib.sh
require_no_instance

T=$(mktemp -d); trap 'cleanup; rm -rf "$T"' EXIT
OUT=${OUT:-$T/shots}; mkdir -p "$OUT"
export XDG_STATE_HOME=$T/state

launch "$T/cfg"
check "one window (WIN-1)" 1 "$(win_count)"
check "app ID (WIN-3)" "$APP" "$(active .class)"
# The nixpkgs godot is a debug build and appends " (DEBUG)" to the title.
check "title (WIN-1)" "Anchorage" "$(active .title | sed 's/ (DEBUG)$//')"
# Hyprland tiles new windows, so only the headless sway (floating) shows the default size.
[ -n "${HEADLESS:-}" ] && check "default size in logical px" "1280 720" "$(active '"\(.size[0]) \(.size[1])"')"
check "config.ini created (CONF-3)" yes "$([ -f "$T/cfg/anchorage/config.ini" ] && echo yes)"
check "keybindings.ini created" yes "$([ -f "$T/cfg/anchorage/keybindings.ini" ] && echo yes)"
shot "$OUT/window.png"

keys -M ctrl q -m ctrl
sleep 1
check "quit closes the window (WIN-4)" 0 "$(win_count)"
check "the process exits" no "$(kill -0 "$PID" 2>/dev/null && echo yes || echo no)"

echo "screenshots in $OUT"
[ "$FAILS" = 0 ]
