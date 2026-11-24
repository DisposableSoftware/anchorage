#! /usr/bin/env nix-shell
#! nix-shell -i bash -p grim wtype
# Spec: ART-3, ART-4, ART-5, ART-6 (real network, SteamGridDB's CDN only).
# Starts the real app (no fake ports) in a sandbox: HOME and every XDG folder are temp
# folders, update checks are off and the ROM folder is empty. Waits for the four cover
# images to land in the sandbox cache, then screenshots the home screen to
# $OUT/<size>-art.png. Run through the headless runner:
#   HEADLESS_RES=1280x720 HEADLESS_SCALE=1 OUT=/tmp/shots \
#     scripts/manual/headless.sh scripts/manual/art.sh 1280x720
cd "$(dirname "$0")/../.." || exit 1
. scripts/manual/lib.sh
[ -n "${HEADLESS:-}" ] || { echo "run through scripts/manual/headless.sh" >&2; exit 2; }
require_no_instance

T=$(mktemp -d); trap 'cleanup; rm -rf "$T"' EXIT
OUT=${OUT:-$T/shots}; mkdir -p "$OUT" "$T/home" "$T/config/anchorage" "$T/roms"
export HOME=$T/home XDG_STATE_HOME=$T/state XDG_CACHE_HOME=$T/cache XDG_DATA_HOME=$T/data
res=${1:-1280x720}
printf '[roms]\ndirectory = %s\n[ports]\ncheck_updates = false\n' "$T/roms" > "$T/config/anchorage/config.ini"

launch "$T/config"
swaymsg fullscreen enable >/dev/null
art=$T/cache/anchorage/art
for _ in $(seq 40); do
  [ "$(find "$art" -type f ! -name '*.part' 2>/dev/null | wc -l)" -ge 4 ] && break
  sleep 1
done
sleep 1.5
shot "$OUT/$res-art.png"
n=$(find "$art" -type f ! -name '*.part' | wc -l)
echo "cached images: $n (expected 4); leftovers: $(find "$art" -name '*.part' | wc -l)"
[ "$n" -eq 4 ] || exit 1
