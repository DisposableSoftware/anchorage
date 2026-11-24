#! /usr/bin/env nix-shell
#! nix-shell -i bash -p jq grim imagemagick
# Spec: LOOK-1, LOOK-9.
# resolutions.sh [SCRIPT]: opens the app fullscreen in its own headless sway at 1280x720,
# 1280x800, 1920x1080, 1920x1200, 2560x1600 and 3840x2160 (scale 1; 16:9 and 16:10) and
# checks the window and its screenshot have the output size in device px and are painted
# to the corner. Screenshots go to $OUT/<size>/ for a look at the layout. With SCRIPT
# (scripts/manual/shots.sh or rom-folder.sh) it runs that at each size instead; SIZES
# picks the sizes: SIZES="1280x720 1280x800" scripts/manual/resolutions.sh scripts/manual/shots.sh
cd "$(dirname "$0")/../.." || exit 1
OUT=${OUT:-$(mktemp -d)}
script=${1:-scripts/manual/resolution-check.sh}
status=0
for res in ${SIZES:-1280x720 1280x800 1920x1080 1920x1200 2560x1600 3840x2160}; do
  echo "== $res"
  mkdir -p "$OUT/$res"
  OUT=$OUT/$res HEADLESS_RES=$res HEADLESS_SCALE=1 scripts/manual/headless.sh "$script" "$res" || status=1
done
echo "screenshots in $OUT"
exit $status
