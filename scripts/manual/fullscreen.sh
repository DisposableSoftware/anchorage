#! /usr/bin/env nix-shell
#! nix-shell -i bash -p jq grim imagemagick sway wtype dbus xdotool xprop
# Spec: WIN-6, CONF-10, CONF-4, WIN-1.
# fullscreen.sh: the app makes itself fullscreen when the environment says gamescope or
# Steam (WIN-6), at the size the compositor gives it, painted to the corner; without those
# variables it stays a 1280x720 window, and [window] fullscreen overrides both ways
# (CONF-10). Unlike resolution-check.sh nothing here asks sway to make it fullscreen.
# Run it from the repo root after `nix build`, outside `nix develop` (see CLAUDE.md):
#   OUT=/tmp/shots scripts/manual/fullscreen.sh
# It runs itself in a headless sway at each of SIZES (default 1280x720 1280x800 1920x1200,
# scale 1). Screenshots of the whole output go to $OUT/<size>/<case>.png.
# IMG=dist/Anchorage-X.Y.Z-x86_64.AppImage runs that AppImage (extract-and-run) instead of
# ./result/bin/anchorage; on NixOS add RUNNER=steam-run and a TMPDIR in your home:
#   mkdir -p ~/.cache/ae && TMPDIR=~/.cache/ae RUNNER=steam-run IMG=dist/... scripts/manual/fullscreen.sh
# X11=0 skips the Xwayland cases: the release build picks X11 first when DISPLAY is set,
# as it is under gamescope, so that is the path Game Mode most likely takes.
cd "$(dirname "$0")/../.." || exit 1
if [ -z "${HEADLESS:-}" ]; then
  OUT=${OUT:-$(mktemp -d)}
  status=0
  for res in ${SIZES:-1280x720 1280x800 1920x1200}; do
    echo "== $res"
    mkdir -p "$OUT/$res"
    # bash, not the nix-shell shebang: one nix-shell temp dir less keeps the socket paths short.
    OUT=$OUT/$res HEADLESS_RES=$res HEADLESS_SCALE=1 bash scripts/manual/headless.sh scripts/manual/fullscreen.sh || status=1
  done
  echo "screenshots in $OUT"
  exit $status
fi
. scripts/manual/lib.sh
require_no_instance

T=$(mktemp -d); trap 'stop_app; rm -rf "$T"' EXIT
OUT=${OUT:-$T}
export XDG_STATE_HOME=$T/state XDG_DATA_HOME=$T/data XDG_CACHE_HOME=$T/cache
GAME_VARS="XDG_CURRENT_DESKTOP GAMESCOPE_WAYLAND_DISPLAY SteamGameId SteamAppId"
# shellcheck disable=SC2086
unset $GAME_VARS
read -r W H < <(swaymsg -t get_outputs | jq -r '.[0].rect | "\(.width) \(.height)"')
MANTLE="srgba(24,24,37,1)"

if [ -n "${IMG:-}" ]; then
  [ -f "$IMG" ] || { echo "no AppImage at $IMG" >&2; exit 2; }
  cp "$IMG" "$T/test.AppImage"; chmod u+wx "$T/test.AppImage"
  # As in appimage.sh: NixOS's binfmt handler would catch the AppImage magic.
  if grep -qs enabled /proc/sys/fs/binfmt_misc/appimage* 2>/dev/null; then
    printf '\0\0\0' | dd of="$T/test.AppImage" bs=1 seek=8 conv=notrunc 2>/dev/null
  fi
  RUNNER=${RUNNER:-}
  [ -n "$RUNNER" ] && RUNNER=$(command -v "$RUNNER")
  printf '#!/bin/sh\nAPPIMAGE_EXTRACT_AND_RUN=1 exec %s %s "$@"\n' "$RUNNER" "$T/test.AppImage" >"$T/bin"
  chmod +x "$T/bin"
  BIN=$T/bin
  echo "running $IMG${RUNNER:+ through $RUNNER}"
fi

# fullscreen_mode x y width height of the app's window, Wayland or Xwayland.
geom() {
  swaymsg -t get_tree | jq -r "[recurse(.nodes[]?, .floating_nodes[]?)
    | select(.app_id == \"$APP\" or .window_properties.class? == \"$APP\")][0]
    // {} | \"\(.fullscreen_mode) \(.rect.x) \(.rect.y) \(.rect.width) \(.rect.height)\""
}
# Pids of the app's windows in this headless sway. Through steam-run, $PID is the sandbox,
# and killing it can leave the app running.
win_pids() {
  swaymsg -t get_tree | jq -r "recurse(.nodes[]?, .floating_nodes[]?)
    | select(.app_id == \"$APP\" or .window_properties.class? == \"$APP\") | .pid"
}
stop_app() {
  local p
  cleanup
  for p in $(win_pids); do kill "$p" 2>/dev/null; done
  wait "$PID" 2>/dev/null; PID=
  for _ in $(seq 25); do [ -z "$(win_pids)" ] && break; sleep 0.2; done
}
pixel() { # pixel FILE X Y
  magick "$1" -format "%[pixel:p{$2,$3}]" info: | sed 's/^srgb(/srgba(/; s/)$/,1)/; s/,1,1)/,1)/'
}

# run_case LABEL fullscreen|windowed CONFIG-LINE DRIVER [VAR=VALUE...]: starts the app with
# only those variables of GAME_VARS set and checks what it did with its window.
run_case() {
  local label=$1 expect=$2 conf=$3 driver=$4 kv
  shift 4
  local cfg=$T/cfg-$label
  check "$label: no window left from before" "" "$(win_pids)"
  mkdir -p "$cfg/anchorage"
  [ -n "$conf" ] && printf '[window]\n%s\n' "$conf" >"$cfg/anchorage/config.ini"
  for kv in "$@"; do export "${kv?}"; done
  if [ "$driver" = x11 ]; then
    # lib.sh's launch finds Wayland windows only, and its driver flag comes first: the last wins.
    XDG_CONFIG_HOME=$cfg DISPLAY=$XDISPLAY "$BIN" --rendering-driver opengl3 --display-driver x11 -- --fake-ports >"$T/$label.log" 2>&1 &
    PID=$!
    # The first X client also waits for sway to start Xwayland.
    for _ in $(seq 150); do [ "$(geom)" != "null null null null null" ] && break; sleep 0.2; done
  else
    LOG=$T/$label.log launch "$cfg" -- --fake-ports
  fi
  # shellcheck disable=SC2086
  unset $GAME_VARS
  if [ "$expect" = fullscreen ] && [ "$driver" = x11 ]; then
    # What the app controls on X11 is the request: _NET_WM_STATE_FULLSCREEN, the state
    # gamescope's window manager resizes a window to the output for. Sway marks the release
    # build's X window fullscreen but leaves it at its first size (the slower debug build is
    # resized, and the same request sent again later with xdotool resizes the release one:
    # sway handles a request that comes too soon after mapping only halfway), so the size
    # is only a note here.
    wait_for "$label: sway has it fullscreen" "geom | cut -d' ' -f1" "1"
    local xwin
    xwin=$(DISPLAY=$XDISPLAY xdotool search --class "$APP" 2>/dev/null | head -1)
    check "$label: _NET_WM_STATE_FULLSCREEN set" yes \
      "$(DISPLAY=$XDISPLAY xprop -id "$xwin" _NET_WM_STATE 2>/dev/null | grep -q _NET_WM_STATE_FULLSCREEN && echo yes)"
    sleep 1
    grim "$OUT/$label.png"
    if [ "$(geom)" = "1 0 0 $W $H" ]; then
      check "$label: bottom-right corner painted" "$MANTLE" "$(pixel "$OUT/$label.png" $((W - 2)) $((H - 2)))"
    else
      echo "NOTE  $label: sway left the X window at $(geom | cut -d' ' -f4,5), not ${W}x$H"
    fi
  elif [ "$expect" = fullscreen ]; then
    wait_for "$label: fullscreen at the output size, ${W}x$H" geom "1 0 0 $W $H"
    sleep 1
    grim "$OUT/$label.png"
    check "$label: screenshot is the output" "$W $H" "$(magick identify -format '%w %h' "$OUT/$label.png")"
    # The hint bar (mantle) reaches the corner: the whole output is painted, not just the
    # 1280x720 the window started with.
    check "$label: bottom-right corner painted" "$MANTLE" "$(pixel "$OUT/$label.png" $((W - 2)) $((H - 2)))"
    check "$label: bottom-left corner painted" "$MANTLE" "$(pixel "$OUT/$label.png" 1 $((H - 2)))"
  else
    wait_for "$label: a 1280x720 window, not fullscreen" "geom | cut -d' ' -f1,4,5" "0 1280 720"
    sleep 1
    grim "$OUT/$label.png"
  fi
  stop_app
}

run_case gamescope-display fullscreen "" wayland GAMESCOPE_WAYLAND_DISPLAY=gamescope-0
run_case desktop-gamescope fullscreen "" wayland XDG_CURRENT_DESKTOP=gamescope
run_case steam-game-id fullscreen "" wayland SteamGameId=15790555012393680896
run_case steam-app-id fullscreen "" wayland SteamAppId=0
run_case desktop windowed "" wayland XDG_CURRENT_DESKTOP=KDE
run_case config-false windowed "fullscreen = false" wayland GAMESCOPE_WAYLAND_DISPLAY=gamescope-0 SteamGameId=1
run_case config-true fullscreen "fullscreen = true" wayland
run_case config-bad fullscreen "fullscreen = maybe" wayland SteamAppId=0

if [ "${X11:-1}" != 0 ]; then
  # Sway starts Xwayland on demand; its children get the DISPLAY it set.
  swaymsg exec "printf %s \"\$DISPLAY\" >$T/display" >/dev/null
  for _ in $(seq 20); do [ -s "$T/display" ] && break; sleep 0.1; done
  XDISPLAY=$(cat "$T/display" 2>/dev/null)
  if [ -z "$XDISPLAY" ]; then
    check "Xwayland in the headless sway" "a DISPLAY" "none"
  else
    run_case x11-gamescope fullscreen "" x11 GAMESCOPE_WAYLAND_DISPLAY=gamescope-0 SteamGameId=1
    run_case x11-desktop windowed "" x11
  fi
fi

[ "$FAILS" = 0 ]
