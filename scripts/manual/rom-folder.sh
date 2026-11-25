#! /usr/bin/env nix-shell
#! nix-shell -i bash -p jq grim wtype
# Spec: ROM-11, ROM-12, ROM-14, ROM-17, LOOK-9 (screenshots of the ROM folder chooser).
# One output size (WxH, default 1280x720); run through headless.sh, with the output set
# to that size:
#   HEADLESS_RES=1280x800 HEADLESS_SCALE=1 scripts/manual/headless.sh scripts/manual/rom-folder.sh 1280x800
# or at every 16:9 and 16:10 size through resolutions.sh:
#   OUT=/tmp/shots scripts/manual/resolutions.sh scripts/manual/rom-folder.sh
# Starts the app with the fake ports, fullscreen, opens the chooser from the options menu
# and saves $OUT/<size>-chooser*.png: the ROM folder, its parent with a folder highlighted,
# a drive, the SD card search while it runs and its results, no card, the folder set in
# config.ini, two chosen folders (one highlighted to remove; the SD card's not found), and the
# ROM missing hint that leads to it.
cd "$(dirname "$0")/../.." || exit 1
. scripts/manual/lib.sh
[ -n "${HEADLESS:-}" ] || { echo "run through scripts/manual/headless.sh" >&2; exit 2; }
require_no_instance

T=$(mktemp -d); trap 'cleanup; rm -rf "$T"' EXIT
OUT=${OUT:-$T/shots}; mkdir -p "$OUT"
export XDG_STATE_HOME=$T/state
res=${1:-1280x720}

open() { # open SCENARIO: the app fullscreen in a fresh config dir
  cfg=$T/cfg-$1; mkdir -p "$cfg/anchorage"
  printf '[appearance]\nflavor = %s\naccent = %s\n' "${FLAVOR:-mocha}" "${ACCENT:-mauve}" \
    > "$cfg/anchorage/config.ini"
  launch "$cfg" -- --fake-ports "$1"
  swaymsg fullscreen enable >/dev/null
  sleep 1.5
}
close() { cleanup; wait "$PID" 2>/dev/null; PID=; sleep 0.3; }
chooser() { keys o -k Down -k Down -k Return; }

open showcase
chooser
shot "$OUT/$res-chooser.png"
keys -k Escape
shot "$OUT/$res-chooser-parent.png"
keys -k Left -k Down -k Return
shot "$OUT/$res-chooser-drive.png"
close

open showcase
chooser
keys -k Return
shot "$OUT/$res-chooser-searching.png"
sleep 2
shot "$OUT/$res-chooser-search.png"
close

open no-card
chooser
keys -k Return
sleep 2
shot "$OUT/$res-chooser-no-card.png"
close

open rom-folders
chooser
shot "$OUT/$res-chooser-folders.png"
keys -k Left -k Up
shot "$OUT/$res-chooser-folders-remove.png"
close

open rom-unplugged
chooser
keys -k Left -k Up
shot "$OUT/$res-chooser-folders-unplugged.png"
close

open rom-config
chooser
shot "$OUT/$res-chooser-config.png"
close

open rom-missing
keys -k Return
shot "$OUT/$res-chooser-rom-missing-hint.png"
close

echo "screenshots in $OUT"
