#! /usr/bin/env nix-shell
#! nix-shell -i bash -p wtype wlrctl jq grim procps
# Spec: PORT-3, PORT-5, PORT-6, PORT-8, PORT-9, PORT-10, PORT-12, PORT-15, ROM-5, HOME-8,
# HOME-10, HOME-13.
# End to end with the real network and real ports, fully sandboxed: HOME and every XDG
# folder are temp folders, the ROMs are copies, and the ports run only from there. Run
# after `nix build`, through the headless runner:
#   ROMS=/path/to/rom/copies OUT=/tmp/shots HEADLESS_RES=1920x1080 HEADLESS_SCALE=1 \
#     scripts/manual/headless.sh scripts/manual/e2e.sh
# Keyboard keys drive the app (wtype): install SpaghettiKart, then 2Ship, Starship and
# Ship of Harkinian queued behind it, refresh, then launch each port for up to
# LAUNCH_SECONDS (default 90): answer its first-run "Generate one now?" prompt with a
# click on Yes (inside the headless sway only), look for its window and its generated
# archive, stop it, then remove one port.
# The release AppImages need a standard /lib64 loader: on NixOS set RUNNER=steam-run,
# which runs Anchorage (and so the ports it starts) in an FHS environment, as on SteamOS.
# Screenshots, Anchorage's log and each port's launch.log go to $OUT; everything else
# is deleted at the end (KEEP=1 keeps the sandbox).
cd "$(dirname "$0")/../.." || exit 1
. scripts/manual/lib.sh
[ -n "${HEADLESS:-}" ] || { echo "run through scripts/manual/headless.sh" >&2; exit 2; }
[ -d "${ROMS:-}" ] || { echo "set ROMS to a folder of ROM files to copy" >&2; exit 2; }
require_no_instance

T=$(mktemp -d "${TMPDIR:-/tmp}/anchorage-e2e.XXXXXX")
OUT=${OUT:-$T/shots}
mkdir -p "$OUT" "$T/home" "$T/config/anchorage" "$T/data" "$T/state" "$T/cache" "$T/tmp" "$T/roms"
REAL_BIN=$(realpath "$BIN")
stop_sandbox() {
  cleanup
  # The ports and their dialogs have SHIP_HOME in the sandbox; everything else started
  # here has the sandbox path on its command line (Anchorage gets it as a user argument).
  for p in soh 2ship starship spaghettikart; do stop_port "$p" 2>/dev/null; done
  pkill -f -- "$T/" 2>/dev/null
  sleep 1
  pkill -9 -f -- "$T/" 2>/dev/null
}
finish() {
  stop_sandbox
  cp "$T/anchorage.log" "$OUT/" 2>/dev/null
  if [ -n "${KEEP:-}" ]; then echo "sandbox kept: $T"; else rm -rf "$T"; fi
}
trap finish EXIT

export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data
export XDG_STATE_HOME=$T/state XDG_CACHE_HOME=$T/cache TMPDIR=$T/tmp
cp "$ROMS"/* "$T/roms/"
printf '[roms]\ndirectory = %s\n' "$T/roms" > "$T/config/anchorage/config.ini"
PORTS=$XDG_DATA_HOME/anchorage/ports
STATE=$XDG_STATE_HOME/anchorage/state.ini
if [ -n "${RUNNER:-}" ]; then
  printf '#!/bin/sh\nexec %s %s "$@"\n' "$RUNNER" "$REAL_BIN" > "$T/run-anchorage"
  chmod +x "$T/run-anchorage"
  BIN=$T/run-anchorage
fi

full() { grim "$OUT/$1.png"; echo "shot  $OUT/$1.png"; }
# wait_until SECONDS COMMAND: polls COMMAND every second; fails after SECONDS.
wait_until() {
  local i
  for ((i = 0; i < $1; i++)); do eval "$2" && return 0; sleep 1; done
  return 1
}
exe() { case $1 in
  soh) echo "$PORTS/soh/current/soh.appimage" ;;
  2ship) echo "$PORTS/2ship/current/2ship.appimage" ;;
  starship) echo "$PORTS/starship/current/starship.appimage" ;;
  spaghettikart) echo "$PORTS/spaghettikart/current/spaghetti.appimage" ;;
esac; }
archive() { case $1 in
  soh) echo oot.o2r ;; 2ship) echo mm.o2r ;; starship) echo sf64.o2r ;; spaghettikart) echo mk64.o2r ;;
esac; }
rom_file() { case $1 in
  soh) echo oot.z64 ;; 2ship) echo mm.z64 ;; starship) echo sf64.z64 ;; spaghettikart) echo mk64.z64 ;;
esac; }
other_windows() { sway_wins | jq -r "[.[] | select(.class != \"$APP\") | \"\(.class) \(.size[0])x\(.size[1])\"] | join(\", \")"; }
# home: focus Anchorage and put the focus on card N (0-based).
card() { focus_app; sleep 0.3; keys -k Left -k Left -k Left; local i; for ((i = 0; i < $1; i++)); do keys -k Right; done; }

LOG=$T/anchorage.log launch "$XDG_CONFIG_HOME" -- "--sandbox=$T/"
[ "$(win_count)" -gt 0 ] || { echo "FAIL  Anchorage did not open"; exit 1; }
wait_until 30 "grep -q 'last_check = [1-9]' '$STATE' 2>/dev/null"
check "update check at start stored its time (PORT-5)" 0 $?
sleep 1
full 01-start

echo "== install SpaghettiKart"
card 3; keys -k Return
sleep 2; full 02-kart-downloading
wait_until 300 "[ -x '$(exe spaghettikart)' ]"
check "SpaghettiKart installed and executable (PORT-3)" 0 $?
sleep 2; full 03-kart-installed

echo "== install 2Ship, queue Starship and SoH behind it"
card 1; keys -k Return
sleep 1; keys -k Right -k Return
keys -k Left -k Left -k Return
sleep 1; full 04-queue
wait_until 900 "[ -x '$(exe 2ship)' ] && [ -x '$(exe starship)' ] && [ -x '$(exe soh)' ]"
check "2Ship, Starship and SoH installed (PORT-12 queue)" 0 $?
sleep 3; full 05-all-installed
for id in soh 2ship starship spaghettikart; do
  stat -c '%a %s %n' "$(exe "$id")"
  check "$id executable is 755" 755 "$(stat -c %a "$(exe "$id")")"
  check "$id leaves no download/ (PORT-3)" no "$([ -d "$PORTS/$id/download" ] && echo yes || echo no)"
done
for f in spaghettikart/data/gamecontrollerdb.txt starship/data/gamecontrollerdb.txt \
  starship/data/config.yml starship/data/assets; do
  check "$f in the data folder (PORT-10)" yes "$([ -e "$PORTS/$f" ] && echo yes || echo no)"
done
grep -E '\.(installed|latest)' "$STATE"

echo "== refresh"
before=$(grep last_check "$STATE")
sleep 1; card 0; keys -k F5
wait_until 30 "[ \"\$(grep last_check '$STATE')\" != '$before' ]"
check "refresh checked again (PORT-5)" 0 $?
sleep 1; full 06-refreshed

# The processes of one port (dialogs it opened included): its environment names its data
# folder, which only this sandbox has.
port_pids() {
  local p
  for p in $(pgrep -u "$(id -u)" .); do
    tr '\0' '\n' 2>/dev/null < "/proc/$p/environ" | grep -qx "SHIP_HOME=$PORTS/$1/data" && echo "$p"
  done
}
stop_port() {
  local p
  for p in $(port_pids "$1"); do kill "$p" 2>/dev/null; done
  sleep 3
  for p in $(port_pids "$1"); do kill -9 "$p" 2>/dev/null; done
}
click() { # click X Y, in output pixels
  local x y
  [ -n "$PTR" ] || wlrctl pointer move 0 0
  read -r x y <<<"$PTR"
  wlrctl pointer move $(($1 - x)) $(($2 - y))
  sleep 0.2; command wlrctl pointer click left; sleep 0.5
}
# Answers the ports' first-run "No O2R files found. Generate one now?" with Yes: a zenity
# dialog (SpaghettiKart) or the port's own popup in the middle of its window. The first
# try focuses the window and presses Return, the second clicks where Yes is (offsets read
# from screenshots at 1920x1080, scale 1).
answer_yes() { # answer_yes TRY
  local target dx dy
  target=$(sway_wins | jq -r '[.[] | select(.class == "zenity")][0] // empty | .class')
  dx=-94; dy=67
  if [ -z "$target" ]; then
    target=$(sway_wins | jq -r "[.[] | select(.class != \"$APP\")][0] // empty | .class")
    dx=-138; dy=27
  fi
  [ -n "$target" ] || return
  swaymsg "[app_id=\"$target\"] focus" >/dev/null; sleep 0.5
  if [ "$1" = 0 ]; then
    wtype -k Shift_L; sleep 0.3; wtype -k Return
  else
    set -- $(sway_wins | jq -r "[.[] | select(.class == \"$target\")][0]
      | \"\((.at[0] + .size[0] / 2) | floor) \((.at[1] + .size[1] / 2) | floor)\"")
    click $(($1 + dx)) $(($2 + dy))
  fi
}

echo "== launch"
n=0
for id in spaghettikart 2ship starship soh; do
  case $id in soh) i=0 ;; 2ship) i=1 ;; starship) i=2 ;; spaghettikart) i=3 ;; esac
  pre=$(printf '%02d' $((7 + n * 4)))
  rm -f "$PORTS/$id/launch.log"
  card $i; keys -k Return
  wait_until 20 "[ -s '$PORTS/$id/launch.log' ]"
  check "$id spawned, output in launch.log (PORT-8)" 0 $?
  placed=$([ -f "$PORTS/$id/data/$(rom_file "$id")" ] && echo yes || echo no)
  echo "      ROM placed before the start: $placed (PORT-9)"
  sleep 1; full "$pre-$id-a-playing"
  seen=""; answered=0
  for ((s = 0; s < ${LAUNCH_SECONDS:-90}; s += 5)); do
    w=$(other_windows); [ -n "$w" ] && seen=$w
    [ -f "$PORTS/$id/data/$(archive "$id")" ] && break
    [ -z "$(port_pids "$id")" ] && break
    if [ -n "$w" ] && [ $answered -lt 2 ] && [ $s -ge 10 ]; then
      full "$pre-$id-b-prompt$answered"
      answer_yes $answered; answered=$((answered + 1))
    fi
    sleep 5
  done
  sleep 5
  full "$pre-$id-c-after"
  echo "      windows: ${seen:-none}"
  echo "      archive $(archive "$id"): $([ -f "$PORTS/$id/data/$(archive "$id")" ] && echo yes || echo no)"
  echo "      still running after the wait: $([ -n "$(port_pids "$id")" ] && echo yes || echo no)"
  stop_port "$id"
  sleep 2
  cp "$PORTS/$id/launch.log" "$OUT/launch-$id.log" 2>/dev/null
  for l in "$PORTS/$id"/data/logs/*.log; do [ -f "$l" ] && tail -60 "$l" > "$OUT/port-$id-$(basename "$l")"; done
  full "$pre-$id-d-back"
  if [ -f "$PORTS/$id/data/$(archive "$id")" ]; then
    check "$id placed ROM deleted after extraction (PORT-9)" no \
      "$([ -f "$PORTS/$id/data/$(rom_file "$id")" ] && echo yes || echo no)"
  fi
  n=$((n + 1))
done

echo "== remove SpaghettiKart"
card 3; keys o; keys -k Down -k Down -k Return
sleep 0.5; full 20-remove-dialog
keys -k Right -k Return
sleep 2; full 21-removed
check "program deleted (PORT-7)" no "$([ -d "$PORTS/spaghettikart/current" ] && echo yes || echo no)"
check "data kept (PORT-7)" yes "$([ -d "$PORTS/spaghettikart/data" ] && echo yes || echo no)"
du -sh "$PORTS"/*/ 2>/dev/null
echo "$FAILS failed"
exit $((FAILS > 0))
