#! /usr/bin/env nix-shell
#! nix-shell -i bash -p wtype jq grim imagemagick
# Spec: HOME-1, HOME-4, HOME-5, HOME-12, HOME-13, LOOK-5, LOOK-6.
# Run at 1280x720, scale 1, after `nix build`:
#   HEADLESS_RES=1280x720 HEADLESS_SCALE=1 scripts/manual/headless.sh scripts/manual/home.sh
# Starts the app with the fake ports (nothing installed), fullscreen. Keyboard keys drive
# focus; the focus ring is found by its colour on the cards' left edges. Starts an install
# and moves focus while it downloads, so the UI must keep answering (HOME-13).
# Screenshots go to $OUT.
cd "$(dirname "$0")/../.." || exit 1
. scripts/manual/lib.sh
[ -n "${HEADLESS:-}" ] || { echo "run through scripts/manual/headless.sh" >&2; exit 2; }
require_no_instance

T=$(mktemp -d); trap 'cleanup; rm -rf "$T"' EXIT
OUT=${OUT:-$T/shots}; mkdir -p "$OUT"
export XDG_STATE_HOME=$T/state

# Mocha's mauve (the default accent), base and mantle, as ImageMagick prints them.
RING="srgb(203,166,247)"
BASE="srgb(30,30,46)"
MANTLE="srgb(24,24,37)"
# Left edge of card N (0-based) at 1280x720: 40 px margin, 282 px cards, 24 px gaps.
edge() { echo $((41 + $1 * 306)); }
pixel() { magick "$1" -format "%[pixel:p{$2,$3}]" info: | sed 's/srgba(\(.*\),1)/srgb(\1)/'; }
ring_on() { # ring_on SHOT: the card with the focus ring, or "none"
  local i
  for i in 0 1 2 3; do
    [ "$(pixel "$1" "$(edge $i)" 200)" = "$RING" ] && { echo "$i"; return; }
  done
  echo none
}

launch "$T/cfg" -- --fake-ports fresh
swaymsg fullscreen enable >/dev/null
sleep 1.5
check "window is 1280x720" "1280 720" "$(size)"
shot "$OUT/start.png"
check "focus starts on the first card (HOME-1)" 0 "$(ring_on "$OUT/start.png")"
check "background is base (LOOK-6)" "$BASE" "$(pixel "$OUT/start.png" 2 2)"
check "hint bar reaches the corner" "$MANTLE" "$(pixel "$OUT/start.png" 1277 717)"

keys -k Return
keys -k Right
shot "$OUT/installing.png"
check "right moves focus while a download runs (HOME-1, HOME-13)" 1 "$(ring_on "$OUT/installing.png")"
keys -k Right -k Right -k Right
shot "$OUT/last.png"
check "focus stops at the last card" 3 "$(ring_on "$OUT/last.png")"

keys o
shot "$OUT/menu.png"
check "options moves focus into the menu (HOME-5)" none "$(ring_on "$OUT/menu.png")"
keys -k Escape
shot "$OUT/closed.png"
check "back returns focus to the card" 3 "$(ring_on "$OUT/closed.png")"

sleep 6
shot "$OUT/installed.png"
echo "look: the first card says Ready in $OUT/installed.png"

keys -M ctrl q -m ctrl
sleep 1
check "quit closes the window" 0 "$(win_count)"

echo "screenshots in $OUT"
[ "$FAILS" = 0 ]
