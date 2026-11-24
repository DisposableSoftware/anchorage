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
pixel() { magick "$1" -format "%[pixel:p{$2,$3}]" info: | sed 's/srgba(\(.*\),1)/srgb(\1)/'; }
# The fake has seven ports, so at 1280x720 the row scrolls (HOME-1): 40 px margin, cards of
# floor((1200 - 4 * 24) / 4.3) = 256 px, 24 px gaps, a 1936 px row in a 1200 px view.
# Screen x of the focus ring's left edge for card N at scroll S.
ring_at() { echo $((40 + $1 * 280 - $2)); }
ring_x() { # ring_x SHOT: x of the first focus-ring pixel across the cards, or "none"
  local x
  x=$(magick "$1" -crop 1280x1+0+200 +repage txt:- | grep -i -m1 '#CBA6F7' | cut -d, -f1)
  echo "${x:-none}"
}

launch "$T/cfg" -- --fake-ports fresh
swaymsg fullscreen enable >/dev/null
sleep 1.5
check "window is 1280x720" "1280 720" "$(size)"
shot "$OUT/start.png"
check "focus starts on the first card (HOME-1)" "$(ring_at 0 0)" "$(ring_x "$OUT/start.png")"
check "background is base (LOOK-6)" "$BASE" "$(pixel "$OUT/start.png" 2 2)"
check "hint bar reaches the corner" "$MANTLE" "$(pixel "$OUT/start.png" 1277 717)"

keys -k Return
keys -k Right
shot "$OUT/installing.png"
check "right moves focus while a download runs (HOME-1, HOME-13)" "$(ring_at 1 0)" \
  "$(ring_x "$OUT/installing.png")"
keys -k Right -k Right -k Right
shot "$OUT/fifth.png"
# The fifth card and part of the sixth in view: 4 * 280 + 256 + 24 + 77 - 1200 = 277.
check "the row scrolls to the fifth card" "$(ring_at 4 277)" "$(ring_x "$OUT/fifth.png")"
keys -k Right -k Right -k Right
shot "$OUT/last.png"
check "focus stops at the last card, scrolled to the end" "$(ring_at 6 736)" "$(ring_x "$OUT/last.png")"

keys o
shot "$OUT/menu.png"
check "options moves focus into the menu (HOME-5)" none "$(ring_x "$OUT/menu.png")"
keys -k Escape
shot "$OUT/closed.png"
check "back returns focus to the card" "$(ring_at 6 736)" "$(ring_x "$OUT/closed.png")"
keys -k Left -k Left -k Left -k Left -k Left -k Left -k Left
shot "$OUT/first.png"
check "left scrolls back to the first card" "$(ring_at 0 0)" "$(ring_x "$OUT/first.png")"

sleep 6
shot "$OUT/installed.png"
echo "look: the first card says Ready in $OUT/installed.png"

keys -M ctrl q -m ctrl
sleep 1
check "quit closes the window" 0 "$(win_count)"

echo "screenshots in $OUT"
[ "$FAILS" = 0 ]
