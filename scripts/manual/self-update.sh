#! /usr/bin/env nix-shell
#! nix-shell -i bash -p jq grim wtype python3 util-linux iproute2
# shellcheck shell=bash
# Spec: UPD-2, UPD-3, UPD-4, UPD-5, UPD-6, UPD-7, UPD-9.
# The real AppImage updates itself: it runs from a temp ~/Applications with APPIMAGE set
# (by its own runtime), a server on 127.0.0.1 stands in for GitHub through the
# ANCHORAGE_RELEASES_URL test hook and offers the next patch version (a copy of the same
# AppImage with a few bytes appended, so its hash differs; its SHA256SUMS and API digest
# match), and the menu is driven with keys: the chip, the entry, the download (throttled so
# the progress shows), the swap, `.previous`, the installer's record, Restart now, the new
# process, and `.previous` gone after it ran 10 s. Run after scripts/build-appimage.sh:
#   mkdir -p ~/.cache/ae && TMPDIR=~/.cache/ae RUNNER=steam-run HEADLESS_RES=1280x720 \
#     HEADLESS_SCALE=1 OUT=/tmp/shots scripts/manual/headless.sh scripts/manual/self-update.sh
# RUNNER as in appimage.sh (steam-run on NixOS, empty elsewhere). The AppImage starts with
# APPIMAGE_EXTRACT_AND_RUN=1: FUSE does not work in the namespace below, so the FUSE mount
# and Steam's process tracking are only checked on a Deck. Screenshots go to $OUT as
# <size>-selfupdate-{chip,menu,progress,restart,restarted}.png. KEEP=1 keeps the sandbox.
#
# It runs in its own user, mount and network namespace: an empty binfmt_misc (on NixOS the
# kernel would hand every file with the AppImage magic to appimage-run, which ignores
# --appimage-version) and only loopback, so nothing reaches the network.
cd "$(dirname "$0")/../.." || exit 1
[ -n "${HEADLESS:-}" ] || { echo "run through scripts/manual/headless.sh" >&2; exit 2; }
if [ -z "${SELF_UPDATE_NS:-}" ]; then
  exec unshare --user --map-root-user --mount --net env SELF_UPDATE_NS=1 bash "$0" "$@"
fi
if [ -d /proc/sys/fs/binfmt_misc ]; then
  mount -t binfmt_misc none /proc/sys/fs/binfmt_misc || { echo "no private binfmt_misc" >&2; exit 2; }
fi
ip link set lo up
. scripts/manual/lib.sh
require_no_instance

VERSION=$(sed -n 's/^config\/version="\(.*\)"$/\1/p' app/project.godot)
IFS=. read -r MAJ MIN PAT <<<"$VERSION"
NEXT=$MAJ.$MIN.$((PAT + 1))
IMG=${1:-dist/Anchorage-$VERSION-x86_64.AppImage}
[ -f "$IMG" ] || { echo "no $IMG: run scripts/build-appimage.sh first" >&2; exit 2; }
RUNNER=${RUNNER:-}
[ -n "$RUNNER" ] && RUNNER=$(command -v "$RUNNER")
res=$(swaymsg -t get_outputs | jq -r '.[0].rect | "\(.width)x\(.height)"')

T=$(mktemp -d)
SRV_PID='' NEW_PID=''
finish() {
  cleanup
  [ -z "$NEW_PID" ] || kill "$NEW_PID" 2>/dev/null
  [ -z "$SRV_PID" ] || kill "$SRV_PID" 2>/dev/null
  if [ -n "${KEEP:-}" ]; then echo "kept $T"; else rm -rf "$T"; fi
}
trap finish EXIT
OUT=${OUT:-$T/shots}; mkdir -p "$OUT"
export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data
export XDG_STATE_HOME=$T/state XDG_CACHE_HOME=$T/cache
mkdir -p "$HOME/Applications" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
A=$HOME/Applications/Anchorage.AppImage
cp "$IMG" "$A"; chmod 755 "$A"
OLD_SHA=$(sha256sum "$A" | cut -d' ' -f1)

# The release: the same AppImage with bytes after its squashfs, which nothing reads.
NAME=Anchorage-$NEXT-x86_64.AppImage
D=$T/srv/download/v$NEXT
mkdir -p "$D" "$T/srv/api"
cp "$IMG" "$D/$NAME"
printf 'anchorage self-update test\n' >>"$D/$NAME"
NEW_SHA=$(sha256sum "$D/$NAME" | cut -d' ' -f1)
SIZE=$(stat -c %s "$D/$NAME")
printf '%s  steam-hero.png\n%s  %s\n' "$(printf '0%.0s' {1..64})" "$NEW_SHA" "$NAME" >"$D/SHA256SUMS"

# The installer's record (INT-33), as install-steamos.sh writes it.
REC=$XDG_STATE_HOME/anchorage-installer/files.sha256
mkdir -p "${REC%/*}"
printf '%s  %s\n%s  %s\n' "$OLD_SHA" "$A" "$(printf '1%.0s' {1..64})" \
  "$XDG_DATA_HOME/applications/io.github.DisposableSoftware.Anchorage.desktop" >"$REC"
REC_REST=$(tail -n 1 "$REC")

# Serves $T/srv, the AppImage at about a tenth of its size per second.
cat >"$T/server.py" <<'EOF'
import http.server, sys, time
class Slow(http.server.SimpleHTTPRequestHandler):
    def copyfile(self, src, dst):
        while chunk := src.read(1 << 18):
            dst.write(chunk)
            if self.path.endswith(".AppImage"):
                time.sleep(float(sys.argv[2]))
http.server.ThreadingHTTPServer.allow_reuse_address = True
handler = lambda *a, **k: Slow(*a, directory=sys.argv[1], **k)
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
print("port", server.server_address[1], flush=True)
server.serve_forever()
EOF
DELAY=$(awk -v s="$SIZE" 'BEGIN { printf "%.3f", 10 / (s / 262144) }')
python3 -I -u "$T/server.py" "$T/srv" "$DELAY" >"$T/server.log" 2>&1 &
SRV_PID=$!
for _ in $(seq 50); do
  PORT=$(sed -n 's/^port \([0-9]*\)$/\1/p' "$T/server.log" | head -1)
  [ -n "$PORT" ] && break
  sleep 0.1
done
[ -n "$PORT" ] || { echo "the test server did not start" >&2; exit 1; }
U=http://127.0.0.1:$PORT
jq -n --arg tag "v$NEXT" --arg name "$NAME" --argjson size "$SIZE" --arg sha "$NEW_SHA" --arg u "$U" '{
  tag_name: $tag, name: "Notes nobody shows", body: "Never rendered", draft: false, prerelease: false,
  assets: [
    {name: $name, size: $size, digest: ("sha256:" + $sha),
     browser_download_url: ($u + "/download/" + $tag + "/" + $name)},
    {name: "SHA256SUMS", size: 200, digest: null,
     browser_download_url: ($u + "/download/" + $tag + "/SHA256SUMS")}]}' >"$T/srv/api/latest"
export ANCHORAGE_RELEASES_URL=$U/api/latest

printf '#!/bin/sh\nexec env APPIMAGE_EXTRACT_AND_RUN=1 %s "%s" "$@"\n' "$RUNNER" "$A" >"$T/run"
chmod +x "$T/run"
BIN=$T/run
pids() { swaymsg -t get_tree | jq -r '.. | objects | select(.app_id? == "'"$APP"'") | .pid'; }
sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

echo "== $VERSION offered $NEXT at $res"
LOG=$T/run1.log launch ""
swaymsg fullscreen enable >/dev/null
OLD_PID=$(pids | head -1)
wait_for "the start checks the test server (UPD-2)" "grep -c 'GET /api/latest' $T/server.log" 1
sleep 1.5
shot "$OUT/$res-selfupdate-chip.png"
keys -k F10
shot "$OUT/$res-selfupdate-menu.png"
keys -k Return
sleep 3
shot "$OUT/$res-selfupdate-progress.png"
check "it downloads next to the AppImage as .new (UPD-4)" yes "$([ -f "$A.new" ] && echo yes)"
check "the AppImage is untouched meanwhile" "$OLD_SHA" "$(sha "$A")"
for _ in $(seq 300); do [ -f "$A.previous" ] && [ ! -f "$A.new" ] && break; sleep 0.2; done
sleep 1
shot "$OUT/$res-selfupdate-restart.png"
check "the AppImage is the new one (UPD-6)" "$NEW_SHA" "$(sha "$A")"
check "and executable" yes "$([ -x "$A" ] && echo yes)"
check "the old one is kept as .previous" "$OLD_SHA" "$(sha "$A.previous")"
check "no .new left" no "$([ -e "$A.new" ] && echo yes || echo no)"
check "the record's AppImage line has the new hash (UPD-7)" "$NEW_SHA  $A" "$(head -n 1 "$REC")"
check "the rest of the record is the same" "$REC_REST" "$(tail -n 1 "$REC")"
check "the AppImage and SHA256SUMS came from the test server" 2 \
  "$(grep -cE "GET /download/v$NEXT/($NAME|SHA256SUMS) " "$T/server.log")"
check "the old process is still running" yes "$(kill -0 "$OLD_PID" 2>/dev/null && echo yes)"
OLD_APPDIR=$(tr '\0' '\n' <"/proc/$OLD_PID/environ" | sed -n 's/^APPDIR=//p')

echo "== Restart now (UPD-9)"
ASKED=$(grep -c "GET /api/latest" "$T/server.log")
keys -k Right -k Return
for _ in $(seq 50); do kill -0 "$OLD_PID" 2>/dev/null || break; sleep 0.2; done
check "the old process quit" no "$(kill -0 "$OLD_PID" 2>/dev/null && echo yes || echo no)"
for _ in $(seq 150); do
  NEW_PID=$(pids | grep -vx "$OLD_PID" | head -1)
  [ -n "$NEW_PID" ] && break
  sleep 0.2
done
check "a new window from a new process" yes "$([ -n "$NEW_PID" ] && echo yes)"
if [ -n "$NEW_PID" ]; then
  env_of() { tr '\0' '\n' <"/proc/$NEW_PID/environ" | sed -n "s/^$1=//p"; }
  check "its APPIMAGE is the same path" "$A" "$(env_of APPIMAGE)"
  check "its APPDIR is its own, not the old one's" yes \
    "$([ -n "$(env_of APPDIR)" ] && [ "$(env_of APPDIR)" != "$OLD_APPDIR" ] && echo yes)"
  check "its executable is the swapped AppImage's" yes \
    "$(case $(readlink "/proc/$NEW_PID/exe") in */usr/bin/anchorage) echo yes ;; esac)"
  sleep 1
  focus_app
  swaymsg fullscreen enable >/dev/null
  sleep 1.5
  shot "$OUT/$res-selfupdate-restarted.png"
  for _ in $(seq 100); do [ -e "$A.previous" ] || break; sleep 0.2; done
  check ".previous is gone once the new copy ran 10 s (UPD-6)" no \
    "$([ -e "$A.previous" ] && echo yes || echo no)"
  check "the next start did not ask the server again within the hour" "$ASKED" \
    "$(grep -c 'GET /api/latest' "$T/server.log")"
fi
check "the restart log was written" yes "$([ -s "$XDG_DATA_HOME/anchorage/restart.log" ] && echo yes)"
echo "screenshots in $OUT"
[ "$FAILS" = 0 ]
