#! /usr/bin/env nix-shell
#! nix-shell -i bash -p jq grim wtype python3
# shellcheck shell=bash
# Spec: PORT-18, PORT-19, PORT-20, PORT-21, PORT-22, PORT-23.
# The real Ports service against a catalog served from 127.0.0.1 through the
# ANCHORAGE_CATALOG_URL test hook: the built-in seven ports plus one made-up port, one
# hostile entry and one that needs a newer Anchorage. HOME and every XDG folder are in a
# temp sandbox. Release checks and cover art still use the real network. Run through
# headless.sh after `nix build`:
#   HEADLESS_RES=1280x720 HEADLESS_SCALE=1 OUT=/tmp/shots scripts/manual/headless.sh scripts/manual/catalog.sh
# Screenshots go to $OUT: catalog-toast.png (the notice), catalog-badge.png (the new card
# beside the focused one, with its New badge), catalog-cached.png (next start, server gone:
# listed from the cache, badge kept), catalog-new.png (the new card focused, badge gone).
# KEEP=1 keeps the sandbox.
cd "$(dirname "$0")/../.." || exit 1
. scripts/manual/lib.sh
[ -n "${HEADLESS:-}" ] || { echo "run through scripts/manual/headless.sh" >&2; exit 2; }
require_no_instance

T=$(mktemp -d)
SRV_PID=
finish() {
  cleanup
  [ -z "$SRV_PID" ] || kill "$SRV_PID" 2>/dev/null
  if [ -n "${KEEP:-}" ]; then echo "kept $T"; else rm -rf "$T"; fi
}
trap finish EXIT
OUT=${OUT:-$T/shots}; mkdir -p "$OUT"
export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data
export XDG_STATE_HOME=$T/state XDG_CACHE_HOME=$T/cache
mkdir -p "$HOME" "$T/srv" "$XDG_CONFIG_HOME/anchorage"
printf '[ports]\ncheck_updates = true\n' > "$XDG_CONFIG_HOME/anchorage/config.ini"
CACHE=$XDG_CACHE_HOME/anchorage/catalog.json
STATE=$XDG_STATE_HOME/anchorage/state.ini

# The catalog: version 2, the shipped ports, then a new one, a hostile one and a future one.
jq '.version = 2 | .ports += [
  {id: "demoport", name: "Demo Port", game: "Demo Game: The Catalog Test",
   description: "A made-up port that only a fetched catalog lists.",
   repo: "DisposableSoftware/anchorage-demo-port", asset_suffix: "-linux.zip",
   archive: ["demo.o2r"], launch: {executable: "demo.appimage", cwd: "data", args: []},
   rom_place: "data_dir", rom_file: "demo.z64",
   first_run: "Only here to show that the list grows",
   roms: [{label: "US", sha1: "0123456789abcdef0123456789abcdef01234567"}]},
  {id: "evil", name: "Evil", game: "Evil", description: "Hostile",
   repo: "evil.example/../x", asset_suffix: ".zip", archive: ["../../.bashrc"],
   launch: {executable: "../../../bin/sh", cwd: "data", args: ["-c", "touch '"$T"'/pwned"]},
   rom_place: "data_dir", rom_file: "../../x.z64",
   roms: [{label: "US", sha1: "0123456789abcdef0123456789abcdef01234567"}]},
  {id: "future", name: "Future", game: "Future", description: "Needs a newer app",
   repo: "x/future", asset_suffix: ".zip", archive: ["f.o2r"],
   launch: {executable: "f", cwd: "data", args: []}, rom_place: "cartridge",
   rom_file: "f.z64", roms: [{label: "US", sha1: "0123456789abcdef0123456789abcdef01234567"}]}
]' app/data/ports.json > "$T/srv/ports.json"

python3 -I -u -m http.server 0 --bind 127.0.0.1 --directory "$T/srv" >"$T/server.log" 2>&1 &
SRV_PID=$!
for _ in $(seq 50); do
  PORT=$(sed -n 's/.* port \([0-9]*\) .*/\1/p' "$T/server.log" | head -1)
  [ -n "$PORT" ] && break
  sleep 0.1
done
[ -n "$PORT" ] || { echo "the test server did not start" >&2; exit 1; }
export ANCHORAGE_CATALOG_URL=http://127.0.0.1:$PORT/ports.json

LOG=$T/run1.log launch ""
swaymsg fullscreen enable >/dev/null
for _ in $(seq 50); do [ -f "$CACHE" ] && break; sleep 0.2; done
sleep 1
shot "$OUT/catalog-toast.png"
check "the catalog was fetched from the test server" 1 "$(grep -c 'GET /ports.json' "$T/server.log")"
check "the fetched catalog is cached (PORT-21)" "$(cat "$T/srv/ports.json")" "$(cat "$CACHE")"
check "the hostile entry is refused (PORT-22)" yes \
  "$(grep -q 'ports.json: evil: ' "$T/run1.log" && echo yes || echo no)"
check "the future entry needs a newer Anchorage (PORT-19)" 1 \
  "$(grep -c 'future: needs a newer Anchorage' "$T/run1.log")"
check "the new port is marked in state.ini (PORT-23)" "new = demoport" "$(grep '^new = ' "$STATE")"
check "the hostile entry ran nothing" no "$([ -e "$T/pwned" ] && echo yes || echo no)"
keys -k Right -k Right -k Right -k Right -k Right -k Right
sleep 0.5
shot "$OUT/catalog-badge.png"
check "the badge stays until the card is focused" "new = demoport" "$(grep '^new = ' "$STATE")"
cleanup; wait "$PID" 2>/dev/null; PID=
kill "$SRV_PID"; SRV_PID=
sleep 0.5

# Next start, test server gone and the last fetch a moment ago: the cache lists the port.
LOG=$T/run2.log launch ""
swaymsg fullscreen enable >/dev/null
sleep 2
keys -k Right -k Right -k Right -k Right -k Right -k Right
sleep 0.5
shot "$OUT/catalog-cached.png"
check "the badge survives a restart (state.ini)" "new = demoport" "$(grep '^new = ' "$STATE")"
keys -k Right
sleep 0.5
shot "$OUT/catalog-new.png"
check "focusing the new card clears its marker" "" "$(grep '^new = ' "$STATE")"
check "no fetch within the hour (PORT-18)" 0 "$(grep -c 'port catalog was not updated' "$T/run2.log")"
cleanup; wait "$PID" 2>/dev/null; PID=
grep -h 'ports.json\|catalog' "$T/run1.log" "$T/run2.log" | grep -v '^ ' | sort -u
echo "screenshots in $OUT"
exit "$FAILS"
