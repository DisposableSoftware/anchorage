#! /usr/bin/env nix-shell
#! nix-shell -i bash -p jq grim wtype curl oxipng pngquant
# Regenerates the README and metainfo screenshots (docs/screenshots/*.png, INT-41, INT-43).
#
# Usage: nix build && scripts/screenshots.sh [OUTDIR]     (OUTDIR defaults to docs/screenshots)
#   BIN=PATH  the app to run (default ./result/bin/anchorage)
#
# What it does:
#   1. Fetches the seven cover images named by `art.url` in app/data/ports.json into a
#      temp folder as <port id>.png. Only https://cdn2.steamgriddb.com/ and
#      https://cdn.steamgriddb.com/ are accepted (as ART-4 does for the app), at most 5 MiB,
#      no redirects. The images are SteamGridDB uploaders' work, so they are for the
#      screenshots only: the script refuses a temp folder inside the repository, and the
#      folder is deleted at the end.
#   2. Starts the app with `--fake-ports SCENARIO` (demo data, no network, no ROMs) in a
#      headless sway at 1280x720, with ANCHORAGE_FAKE_ART_DIR pointing at those images
#      (ART-8) and a fresh sandbox for every XDG folder, so no real config, state or path
#      shows up.
#   3. Drives it with keys and saves the five shots, optimised with pngquant and oxipng
#      (each must stay under 400 KB, INT-43):
#        home.png        showcase: seven cards with real art, the first one focused
#        installing.png  showcase: Starship downloading, its first-launch note in the panel
#        rom-folder.png  rom-unplugged: the chooser with two chosen folders, one Not found
#        menu.png        self-update: the Start menu with Update showing, the chip in the bar
#        latte.png       first-run in Catppuccin Latte with blue: a first-launch note focused
#
# Look at every image afterwards: the keys are timed for the headless sway, not checked.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAX_KB=400

if [ -z "${HEADLESS:-}" ]; then
  OUTDIR=$(realpath -m "${1:-$ROOT/docs/screenshots}")
  T=$(mktemp -d "${TMPDIR:-/tmp}/anchorage-shots.XXXXXX") || exit 1
  trap 'rm -rf "$T"' EXIT
  case "$(realpath "$T")/" in
    "$ROOT"/*) echo "screenshots.sh: refusing to put cover art inside the repository" >&2; exit 2 ;;
  esac
  mkdir -p "$T/art"
  for id in $(jq -r '.ports[].id' "$ROOT/app/data/ports.json"); do
    url=$(jq -r --arg id "$id" '.ports[] | select(.id == $id) | .art.url // empty' "$ROOT/app/data/ports.json")
    [ -n "$url" ] || { echo "screenshots.sh: $id has no art in the catalog" >&2; exit 2; }
    if ! [[ $url =~ ^https://cdn2?\.steamgriddb\.com/[A-Za-z0-9/._-]+$ ]]; then
      echo "screenshots.sh: refusing art host for $id: $url" >&2; exit 2
    fi
    curl -fsS --proto '=https' --max-redirs 0 --max-filesize 5242880 -o "$T/art/$id.png" "$url" \
      || { echo "screenshots.sh: could not fetch the art for $id" >&2; exit 2; }
    [ "$(head -c 4 "$T/art/$id.png" | tail -c 3)" = PNG ] \
      || { echo "screenshots.sh: the art for $id is not a PNG" >&2; exit 2; }
  done
  mkdir -p "$OUTDIR"
  # sway's socket path has a length limit, and nix-shell's TMPDIR is long: headless.sh gets /tmp.
  ANCHORAGE_FAKE_ART_DIR=$T/art SHOTS_TMP=$T SHOTS_OUT=$OUTDIR BIN=${BIN:-$ROOT/result/bin/anchorage} \
    HEADLESS_RES=1280x720 HEADLESS_SCALE=1 TMPDIR=/tmp \
    "$ROOT/scripts/manual/headless.sh" "$ROOT/scripts/screenshots.sh"
  exit $?
fi

cd "$ROOT" || exit 1
. scripts/manual/lib.sh
require_no_instance
T=$SHOTS_TMP
RAW=$T/raw; mkdir -p "$RAW"
# A fresh sandbox, so nothing of the real home or session reaches a picture.
export HOME=$T/home XDG_STATE_HOME=$T/state XDG_CACHE_HOME=$T/cache XDG_DATA_HOME=$T/data
mkdir -p "$HOME"
trap 'cleanup' EXIT

open() { # open SCENARIO FLAVOR ACCENT
  cfg=$T/cfg-$1-$2-$3; mkdir -p "$cfg/anchorage"
  printf '[appearance]\nflavor = %s\naccent = %s\n' "$2" "$3" > "$cfg/anchorage/config.ini"
  launch "$cfg" -- --fake-ports "$1"
  swaymsg fullscreen enable >/dev/null
  sleep 2
}
close() { cleanup; wait "$PID" 2>/dev/null; PID=; sleep 0.3; }

open showcase mocha mauve
shot "$RAW/home.png"
keys -k Right -k Right
shot "$RAW/installing.png"
close

open rom-unplugged mocha mauve
keys o -k Down -k Down -k Return
sleep 1
shot "$RAW/rom-folder.png"
close

open self-update mocha mauve
sleep 6   # the "is available" toast hides itself
keys -k F10
shot "$RAW/menu.png"
close

open first-run latte blue
keys -k Right -k Right
shot "$RAW/latte.png"
close

status=0
for name in home installing rom-folder menu latte; do
  [ -s "$RAW/$name.png" ] || { echo "missing shot: $name" >&2; status=1; continue; }
  pngquant --force --quality 85-100 --output "$RAW/$name.q.png" "$RAW/$name.png" 2>/dev/null \
    && mv "$RAW/$name.q.png" "$RAW/$name.png"
  oxipng -o 4 --strip safe -q "$RAW/$name.png"
  kb=$(( ($(stat -c %s "$RAW/$name.png") + 1023) / 1024 ))
  if [ "$kb" -ge "$MAX_KB" ]; then echo "$name.png is $kb KB, over $MAX_KB" >&2; status=1; fi
  cp "$RAW/$name.png" "$SHOTS_OUT/$name.png"
  echo "$SHOTS_OUT/$name.png  ${kb} KB"
done
exit $status
