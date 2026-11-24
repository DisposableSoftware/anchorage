#! /usr/bin/env nix-shell
#! nix-shell -i bash -p jq grim wtype
# Spec: LOOK-2, LOOK-5, LOOK-6, HOME-1 .. HOME-12, PORT-17 (screenshots).
# One output size (WxH, default 1280x720); run through headless.sh, with the output set
# to that size:
#   HEADLESS_RES=1280x720 HEADLESS_SCALE=1 scripts/manual/headless.sh scripts/manual/shots.sh 1280x720
# Starts the app with the fake ports (`--fake-ports SCENARIO`) in every scenario, fullscreen
# as gamescope runs it, and saves a screenshot of each to $OUT/<size>-<scenario>.png, plus
# the options menu, the Remove dialog and the latte flavour. FLAVOR and ACCENT override
# the appearance for the whole run.
cd "$(dirname "$0")/../.." || exit 1
. scripts/manual/lib.sh
[ -n "${HEADLESS:-}" ] || { echo "run through scripts/manual/headless.sh" >&2; exit 2; }
require_no_instance

T=$(mktemp -d); trap 'cleanup; rm -rf "$T"' EXIT
OUT=${OUT:-$T/shots}; mkdir -p "$OUT"
export XDG_STATE_HOME=$T/state
res=${1:-1280x720}

config() { # config DIR FLAVOR ACCENT
  mkdir -p "$1/anchorage"
  printf '[appearance]\nflavor = %s\naccent = %s\n' "$2" "$3" > "$1/anchorage/config.ini"
}

# open SCENARIO [FLAVOR ACCENT]: starts the app fullscreen in a fresh config dir.
open() {
  cfg=$T/cfg-$1-${2:-x}; config "$cfg" "${2:-${FLAVOR:-mocha}}" "${3:-${ACCENT:-mauve}}"
  launch "$cfg" -- --fake-ports "$1"
  swaymsg fullscreen enable >/dev/null
  sleep 1.5
}

close() { cleanup; wait "$PID" 2>/dev/null; PID=; sleep 0.3; }

for scenario in showcase fresh installing updating rom-missing error offline playing first-run; do
  open "$scenario"
  shot "$OUT/$res-$scenario.png"
  close
done

open showcase
keys -k Right
shot "$OUT/$res-showcase-second.png"
# A catalog of more than four ports scrolls the row with focus (HOME-1).
keys -k Right -k Right -k Right -k Right -k Right
shot "$OUT/$res-showcase-last.png"
keys -k Left -k Left -k Left
shot "$OUT/$res-showcase-back.png"
keys -k Left -k Left -k Left -k Left o
shot "$OUT/$res-menu.png"
keys -k Down -k Down -k Return
shot "$OUT/$res-confirm.png"
close

open first-run
keys -k Right -k Right
shot "$OUT/$res-first-run-starship.png"
close

open rom-missing
keys -k Return
shot "$OUT/$res-rom-missing-accept.png"
close

open showcase latte blue
shot "$OUT/$res-latte.png"
close

echo "screenshots in $OUT"
