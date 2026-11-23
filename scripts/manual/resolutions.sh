#! /usr/bin/env nix-shell
#! nix-shell -i bash -p jq grim imagemagick
# Spec: LOOK-1.
# Opens the app fullscreen in its own headless sway at 1280x720, 1280x800, 1920x1080 and
# 3840x2160 (scale 1) and checks the window and its screenshot have the output size in
# device px and are painted to the corner. Screenshots go to $OUT/<size>/ for a look at the layout.
cd "$(dirname "$0")/../.." || exit 1
OUT=${OUT:-$(mktemp -d)}
status=0
for res in 1280x720 1280x800 1920x1080 3840x2160; do
  echo "== $res"
  mkdir -p "$OUT/$res"
  OUT=$OUT/$res HEADLESS_RES=$res HEADLESS_SCALE=1 scripts/manual/headless.sh scripts/manual/resolution-check.sh "$res" || status=1
done
echo "screenshots in $OUT"
exit $status
