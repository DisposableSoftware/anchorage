#! /usr/bin/env nix-shell
#! nix-shell -i bash -p wtype jq grim squashfsTools binutils desktop-file-utils
# Spec: INT-25, INT-26, WIN-1, WIN-3, WIN-4.
# Checks a built AppImage: the file itself, what is inside it, and that it starts, shows
# the home screen under the app ID and quits. Run after `scripts/build-appimage.sh`:
#   scripts/manual/headless.sh scripts/manual/appimage.sh [dist/Anchorage-X-x86_64.AppImage]
# MODE picks how the AppImage starts:
#   extract (default)  APPIMAGE_EXTRACT_AND_RUN=1: no FUSE needed
#   fuse               the AppImage as it is: needs FUSE 2 and fusermount
#   mount              `--appimage-mount`, then AppRun from the mount (the same FUSE mount,
#                      for hosts where the AppImage's binary needs RUNNER to start)
# RUNNER is a command put in front (default none). On NixOS the binary needs a stock
# /lib64 loader, so use RUNNER=steam-run there; on SteamOS and other distros leave it empty.
# CLEAN=1 also runs with an empty environment apart from the display and XDG variables.
# Uses temp XDG dirs. Screenshots go to $OUT.
cd "$(dirname "$0")/../.." || exit 1
. scripts/manual/lib.sh
require_no_instance

MODE=${MODE:-extract}
RUNNER=${RUNNER:-}
[ -n "$RUNNER" ] && RUNNER=$(command -v "$RUNNER")
T=$(mktemp -d)
IMG=${1:-$(ls -t dist/Anchorage-*-x86_64.AppImage 2>/dev/null | head -1)}
[ -f "$IMG" ] || { echo "no AppImage: run scripts/build-appimage.sh first" >&2; exit 2; }
OUT=${OUT:-$T/shots}; mkdir -p "$OUT"
MNT_PID=
cleanup_all() {
  cleanup
  [ -n "$MNT_PID" ] && kill "$MNT_PID" 2>/dev/null
  rm -rf "$T"
}
trap cleanup_all EXIT

# Work on a copy. NixOS registers a binfmt handler (appimage-run) that catches every file
# with the AppImage magic at byte 8, even when run through a wrapper. Clearing the magic
# in the copy makes the kernel run the static runtime directly, which is what SteamOS does.
cp "$IMG" "$T/test.AppImage"; chmod u+wx "$T/test.AppImage"
if grep -qs enabled /proc/sys/fs/binfmt_misc/appimage* 2>/dev/null; then
  printf '\0\0\0' | dd of="$T/test.AppImage" bs=1 seek=8 conv=notrunc 2>/dev/null
  echo "note: binfmt appimage handler is on; ran a copy without the magic bytes"
fi
A=$T/test.AppImage

echo "== the file (INT-25)"
size=$(stat -c %s "$IMG")
echo "size: $size bytes"
check "under 60 MB" yes "$([ "$size" -lt 62914560 ] && echo yes)"
check "executable" yes "$([ -x "$IMG" ] && echo yes)"
check "name has the version and arch" yes "$(basename "$IMG" | grep -qE '^Anchorage-[0-9]+\.[0-9]+\.[0-9]+-x86_64\.AppImage$' && echo yes)"
check "ELF runtime, type 2 magic" "414902" "$(dd if="$IMG" bs=1 skip=8 count=3 2>/dev/null | od -An -tx1 | tr -d ' \n')"
off=$(readelf -h "$IMG" | awk '/Start of section headers/ {s=$5} /Size of section headers/ {z=$5} /Number of section headers/ {n=$5} END {print s + z * n}')
echo "squashfs offset: $off"

echo "== the contents (INT-25, INT-26)"
unsquashfs -q -d "$T/x" -o "$off" "$IMG" >/dev/null
ID=io.github.DisposableSoftware.Anchorage
for f in AppRun usr/bin/anchorage "$ID.desktop" "$ID.svg" .DirIcon \
         "usr/share/applications/$ID.desktop" "usr/share/metainfo/$ID.metainfo.xml" \
         "usr/share/icons/hicolor/scalable/apps/$ID.svg" usr/share/doc/anchorage/config.example.ini; do
  check "has $f" yes "$([ -e "$T/x/$f" ] && echo yes)"
done
check "AppRun and binary are executable" yes "$([ -x "$T/x/AppRun" ] && [ -x "$T/x/usr/bin/anchorage" ] && echo yes)"
check "desktop entry validates" "" "$(desktop-file-validate "$T/x/$ID.desktop" 2>&1)"
B=$T/x/usr/bin/anchorage
echo "needs: $(readelf -d "$B" | awk '/NEEDED/ {gsub(/[][]/, "", $5); printf "%s ", $5}')"
echo "interpreter: $(readelf -l "$B" | sed -n 's/.*interpreter: \(.*\)]/\1/p')"
check "no RPATH or RUNPATH" "" "$(readelf -d "$B" | grep -e RPATH -e RUNPATH)"
check "interpreter is the stock one" /lib64/ld-linux-x86-64.so.2 "$(readelf -l "$B" | sed -n 's/.*interpreter: \(.*\)]/\1/p')"
check "nothing from /nix/store in the binary" 0 "$(grep -ac /nix/store "$B")"
check "needs only glibc libraries" "" "$(readelf -d "$B" | awk '/NEEDED/ {gsub(/[][]/, "", $5); print $5}' | grep -vE '^(libc|libm|libdl|libpthread|librt|ld-linux-x86-64)\.so')"
check "release build: no (DEBUG) title" 0 "$(grep -ac '(DEBUG)' "$B")"

echo "== start, window, quit (INT-25, WIN-1, WIN-3, WIN-4), mode $MODE"
export XDG_STATE_HOME=$T/state XDG_DATA_HOME=$T/data XDG_CACHE_HOME=$T/cache
mkdir -p "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
case $MODE in
  extract) export APPIMAGE_EXTRACT_AND_RUN=1 ;;
  mount)
    "$A" --appimage-mount >"$T/mnt" 2>"$T/mnt.err" &
    MNT_PID=$!
    for _ in $(seq 50); do [ -s "$T/mnt" ] && break; sleep 0.1; done
    check "FUSE mount works" yes "$([ -s "$T/mnt" ] && [ -x "$(head -1 "$T/mnt")/AppRun" ] && echo yes)"
    ;;
esac
wrapper() { # wrapper FILE ENVPREFIX...: a BIN that starts the AppImage per MODE
  local f=$1; shift
  case $MODE in
    mount) target="$(head -1 "$T/mnt")/AppRun" ;;
    *) target=$A ;;
  esac
  printf '#!/bin/sh\nexec %s %s %s "$@"\n' "$*" "$RUNNER" "$target" >"$f"
  chmod +x "$f"
}

run_once() { # run_once LABEL ENV...: launch, check, screenshot, quit
  local label=$1; shift
  wrapper "$T/bin-$label" "$@"
  BIN=$T/bin-$label
  launch "$T/cfg-$label" -- --fake-ports
  check "$label: one window" 1 "$(win_count)"
  check "$label: app ID" "$APP" "$(active .class)"
  check "$label: title has no (DEBUG)" "Anchorage" "$(title)"
  [ -n "${HEADLESS:-}" ] && check "$label: default size" "1280 720" "$(size)"
  wpid=$(active .pid)
  exe=$(readlink "/proc/$wpid/exe" 2>/dev/null)
  echo "$label: window pid $wpid, exe $exe"
  check "$label: executable is inside the AppImage" yes "$(case $exe in */usr/bin/anchorage) echo yes ;; esac)"
  if [ -r "/proc/$wpid/environ" ]; then
    echo "$label: APPIMAGE=$(tr '\0' '\n' <"/proc/$wpid/environ" | sed -n 's/^APPIMAGE=//p') APPDIR=$(tr '\0' '\n' <"/proc/$wpid/environ" | sed -n 's/^APPDIR=//p')"
  fi
  check "$label: config.ini created in XDG_CONFIG_HOME" yes "$([ -f "$T/cfg-$label/anchorage/config.ini" ] && echo yes)"
  check "$label: user:// is under XDG_DATA_HOME" yes "$([ -d "$XDG_DATA_HOME/anchorage" ] && echo yes)"
  shot "$OUT/$label-home.png"
  keys -M ctrl q -m ctrl
  sleep 1
  check "$label: quit closes the window" 0 "$(win_count)"
  check "$label: the process exits" no "$(kill -0 "$wpid" 2>/dev/null && echo yes || echo no)"
  cleanup; wait "$PID" 2>/dev/null
}

run_once normal env
if [ -n "${CLEAN:-}" ]; then
  # No inherited PATH or library path, as a launcher with a bare environment would give.
  run_once clean env -i "HOME=$HOME" "PATH=/nonexistent" "LD_LIBRARY_PATH=" \
    "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" \
    "XDG_CONFIG_HOME=$T/cfg-clean" "XDG_STATE_HOME=$XDG_STATE_HOME" "XDG_DATA_HOME=$XDG_DATA_HOME" \
    "XDG_CACHE_HOME=$XDG_CACHE_HOME" ${APPIMAGE_EXTRACT_AND_RUN:+APPIMAGE_EXTRACT_AND_RUN=1}
fi

echo "screenshots in $OUT"
[ "$FAILS" = 0 ]
