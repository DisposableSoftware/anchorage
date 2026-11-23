#! /usr/bin/env nix-shell
#! nix-shell -i bash -p jq grim imagemagick
# Spec: LOOK-1. One output size (WxH); run through resolutions.sh. The compositor makes
# the window fullscreen, as gamescope does. A size the app sets on itself after startup
# is not used here (see the CONF-4 note in spec/configuration.md).
cd "$(dirname "$0")/../.." || exit 1
. scripts/manual/lib.sh
[ -n "${HEADLESS:-}" ] || { echo "run through scripts/manual/resolutions.sh" >&2; exit 2; }
require_no_instance

T=$(mktemp -d); trap 'cleanup; rm -rf "$T"' EXIT
OUT=${OUT:-$T}
export XDG_STATE_HOME=$T/state
w=${1%x*}; h=${1#*x}

launch "$T/cfg" -- --fake-ports
swaymsg fullscreen enable >/dev/null
sleep 2
check "window size at $1" "$w $h" "$(active '"\(.size[0]) \(.size[1])"')"
shot "$OUT/window.png"
check "screenshot in device px" "$w $h" "$(magick identify -format '%w %h' "$OUT/window.png")"
# The whole window is painted, not just the 1280x720 the app starts with: the corner is
# the hint bar, mocha's mantle.
check "bottom-right corner is painted" "srgba(24,24,37,1)" "$(magick "$OUT/window.png" -format '%[pixel:p{'$((w - 2))','$((h - 2))'}]' info: | sed 's/^srgb(/srgba(/; s/)$/,1)/; s/,1,1)/,1)/')"
[ "$FAILS" = 0 ]
