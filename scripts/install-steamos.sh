#!/usr/bin/env bash
# Installs Anchorage on SteamOS from Desktop Mode, or on any x86_64 Linux with Steam:
#
#   curl -fsSL https://github.com/DisposableSoftware/anchorage/releases/latest/download/install-steamos.sh | bash
#
# It downloads the release AppImage to ~/Applications/Anchorage.AppImage, checks it
# against the release's SHA256SUMS, adds a desktop entry and icon, and adds an
# "Anchorage" shortcut with artwork to every Steam account. Steam must be closed for that:
# when it runs, the script closes it, makes the change and starts it again.
# Spec: INT-28, INT-29, INT-33, INT-34, INT-35 in spec/integration.md, with the reasons.
#
# Options (through curl: ... | bash -s -- --uninstall):
#   --version X.Y.Z      install that release instead of the latest
#   --dry-run            say what would change, change nothing
#   --uninstall          remove what this script added (not Anchorage's own data)
#   --no-steam-restart   never close Steam: stop with instructions while it runs
#   --help
#
# Needs bash, curl and coreutils. It reads nothing from standard input.
# For tests only: ANCHORAGE_API_URL and ANCHORAGE_DOWNLOAD_BASE replace the GitHub URLs,
# ANCHORAGE_COUNTDOWN and ANCHORAGE_STEAM_WAIT the 5 s countdown and the 60 s wait for Steam.
set -euo pipefail

# scripts/release-assets.sh sets this in the copy attached to a release.
PINNED_VERSION=""

APP_ID=io.github.DisposableSoftware.Anchorage
APP_NAME=Anchorage
API=${ANCHORAGE_API_URL:-https://api.github.com/repos/DisposableSoftware/anchorage}
DOWNLOADS=${ANCHORAGE_DOWNLOAD_BASE:-https://github.com/DisposableSoftware/anchorage/releases/download}
ART_ASSETS=(steam-portrait.png steam-wide.png steam-hero.png steam-logo.png steam-icon.png)
ART_SUFFIXES=(p "" _hero _logo _icon)
ICON_ASSET=$APP_ID.svg
MARKER=X-Anchorage-Installer=install-steamos.sh

say() { short "$*"; printf '%s\n' "$REPLY"; }
step() { printf '\n==> %s\n' "$*"; }
short() { REPLY=$*; [[ -z ${HOME:-} ]] || REPLY=${REPLY//"$HOME"\//\~/}; } # paths in HOME as ~/...
info() { short "$*"; printf '    %s\n' "$REPLY"; }
warn() { short "$*"; printf 'warning: %s\n' "$REPLY" >&2; }
die() { short "$*"; printf '\nerror: %s\n' "$REPLY" >&2; exit 1; }

usage() {
  cat <<'EOF'
Installs Anchorage (AppImage, desktop entry, Steam shortcut with artwork).
Usage: install-steamos.sh [--version X.Y.Z] [--dry-run] [--uninstall] [--no-steam-restart]
       curl -fsSL https://github.com/DisposableSoftware/anchorage/releases/latest/download/install-steamos.sh | bash -s -- [options]
EOF
}

# ---- small helpers ----------------------------------------------------------

file_sig() { # file_sig FILE -> REPLY: size, inode and modification time, or "missing"
  REPLY=$(stat -c '%s %i %y' -- "$1" 2>/dev/null) || REPLY=missing
}

sha256() { # sha256 FILE -> REPLY
  local line
  line=$(sha256sum -- "$1") || return 1
  REPLY=${line%% *}
}

same_sha() { # same_sha FILE HASH: the file exists and has that hash
  [[ -f $1 ]] || return 1
  sha256 "$1" || return 1
  [[ $REPLY == "$2" ]]
}

# A connection that stalls (under 1 KiB/s for a minute) fails instead of hanging.
CURL_OPTS=(-fL --retry 3 --connect-timeout 20 --speed-limit 1024 --speed-time 60)

fetch() { # fetch URL DEST [progress]
  local -a opts=("${CURL_OPTS[@]}" -o "$2")
  if [[ ${3:-} == progress && -t 2 ]]; then opts+=(--progress-bar); else opts+=(-sS); fi
  curl "${opts[@]}" -- "$1"
}

steam_running() {
  local f pid comm
  if command -v pgrep >/dev/null 2>&1 && pgrep -x steam >/dev/null 2>&1; then
    return 0
  fi
  for f in "$HOME/.steam/steam.pid" "$HOME/.var/app/com.valvesoftware.Steam/.steam/steam.pid"; do
    [[ -r $f ]] || continue
    pid=
    read -r pid <"$f" || true
    [[ $pid =~ ^[0-9]+$ && -r /proc/$pid/comm ]] || continue
    read -r comm <"/proc/$pid/comm" || true
    [[ $comm == steam ]] && return 0
  done
  return 1
}

steam_flatpak_running() {
  command -v flatpak >/dev/null 2>&1 || return 1
  flatpak ps --columns=application 2>/dev/null | grep -qxF com.valvesoftware.Steam
}

steam_up() { # steam_up KIND (native or flatpak): that Steam is running
  if [[ $1 == flatpak ]]; then steam_flatpak_running; else steam_running; fi
}

# ---- closing and restarting Steam (INT-35) -----------------------------------
# A Deck's controller is a mouse and keyboard in Desktop Mode only while Steam runs, so the
# user can't be asked to quit Steam and then press a key: the script closes Steam and
# starts it again itself, when it can start it again in the user's desktop.

steam_closable() { # -> 0, or 1 with REPLY saying why this run can't close and restart Steam
  REPLY=
  if [[ -n $NO_RESTART ]]; then
    REPLY=" "
  elif [[ -n ${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-} ]]; then
    REPLY="Over SSH it can't start Steam again on the Deck's screen, so it doesn't close it."
  elif [[ -z ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
    REPLY="Without a desktop (no DISPLAY or WAYLAND_DISPLAY) it can't start Steam again, so it doesn't close it."
  elif [[ -n ${SteamGameId:-}${SteamAppId:-} ]]; then
    REPLY="This terminal was started by Steam, and closing Steam would close it too. Run the command from Konsole in Desktop Mode."
  elif ! steam_flatpak_running && ! command -v steam >/dev/null 2>&1; then
    REPLY="There is no steam command to close Steam with."
  fi
  [[ -z $REPLY ]]
}

# steam_check: before a change to shortcuts.vdf or the artwork. Returns at once when Steam
# is not running, stops with instructions when this run can't close and restart it, and
# otherwise sets STEAM_CLOSE: steam_close closes it, after the downloads.
steam_check() {
  steam_running || return 0
  if ! steam_closable; then
    if [[ $REPLY == " " ]]; then REPLY=; else REPLY=$'\n'$REPLY; fi
    die "Steam is running. Steam rewrites its shortcuts file when it exits, so the shortcut
can't be changed now. Nothing was changed.$REPLY
Exit Steam first: in Desktop Mode, right-click the Steam icon in the system tray and
choose Exit (or run: steam -shutdown). When it has closed, run the same command again."
  fi
  STEAM_CLOSE=1
  if [[ -n $DRY ]]; then
    if steam_flatpak_running; then
      info "Steam is running: would close it (flatpak run com.valvesoftware.Steam -shutdown), make the"
      info "changes and start it again (flatpak run com.valvesoftware.Steam -silent)"
    else
      info "Steam is running: would close it (steam -shutdown), make the changes and start it"
      info "again (steam -silent)"
    fi
  fi
}

steam_close() {
  local n=$COUNTDOWN
  step "Closing Steam"
  info "Steam must be closed while its shortcuts change. It closes now and starts again by"
  info "itself in a few seconds. Press Ctrl+C in the next $n seconds to cancel: nothing has"
  info "been changed yet."
  printf '    closing Steam in'
  while ((n > 0)); do
    printf ' %s' "$n"
    sleep 1
    n=$((n - 1))
  done
  printf '\n'
  # From here on Steam is closing, and the EXIT trap must get to start it again.
  trap '' INT
  if steam_flatpak_running; then steam_quit flatpak || steam_gave_up; fi
  if steam_running; then
    command -v steam >/dev/null 2>&1 || steam_gave_up
    steam_quit native || steam_gave_up
  fi
  sleep 2 # as Steam ROM Manager does: let what Steam started finish exiting
}

steam_quit() { # steam_quit KIND: asks that Steam to quit, and waits for it to exit
  local helper waited=0
  STEAM_CLOSED+=("$1")
  if [[ $1 == flatpak ]]; then
    info "asking Steam to quit: flatpak run com.valvesoftware.Steam -shutdown"
    flatpak run com.valvesoftware.Steam -shutdown </dev/null >/dev/null 2>&1 &
  else
    info "asking Steam to quit: steam -shutdown"
    steam -shutdown </dev/null >/dev/null 2>&1 &
  fi
  helper=$!
  printf '    waiting for Steam to exit'
  while kill -0 "$helper" 2>/dev/null || steam_up "$1"; do
    if ((waited >= STEAM_WAIT)); then
      printf '\n'
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
    printf '.'
  done
  printf ' closed\n'
}

steam_gave_up() {
  trap - INT
  die "Steam did not close within $STEAM_WAIT seconds, so nothing was changed, and Steam was
not forced to close. If Steam shows a question or a game is running, close it, then run
the same command again."
}

detach() { # runs a command in a session of its own, so that it outlives the terminal
  if command -v setsid >/dev/null 2>&1; then
    setsid -f "$@" </dev/null >/dev/null 2>&1
  else
    nohup "$@" </dev/null >/dev/null 2>&1 &
  fi
}

# steam_restart: starts the Steam that steam_close closed, the way Desktop Mode starts it
# (/etc/xdg/autostart/steam.desktop: steam -silent), unless it runs again already. Also
# from the EXIT trap, so that a failure after closing Steam still brings it back.
steam_restart() {
  local k start=()
  ((${#STEAM_CLOSED[@]} > 0)) || return 0
  trap - INT
  for k in "${STEAM_CLOSED[@]}"; do steam_up "$k" || start+=("$k"); done
  STEAM_CLOSED=()
  ((${#start[@]} > 0)) || return 0
  step "Starting Steam again"
  for k in "${start[@]}"; do
    if [[ $k == flatpak ]]; then
      info "flatpak run com.valvesoftware.Steam -silent"
      detach flatpak run com.valvesoftware.Steam -silent || warn "Could not start Steam again: start it from the application menu."
    else
      info "steam -silent"
      detach steam -silent || warn "Could not start Steam again: start it from the application menu."
    fi
  done
  RESTARTED=1
}

# CRC-32 (IEEE, as zlib) of a string's bytes, as an unsigned number in REPLY.
crc32() {
  local -a bytes=()
  local c=0xFFFFFFFF b k
  mapfile -t bytes < <(printf '%s' "$1" | od -An -v -tu1 -w1)
  for b in "${bytes[@]}"; do
    c=$((c ^ b))
    for k in 1 2 3 4 5 6 7 8; do
      c=$(((c >> 1) ^ (0xEDB88320 & -(c & 1))))
    done
  done
  REPLY=$(((c ^ 0xFFFFFFFF) & 0xFFFFFFFF))
}

# The ID Steam gives a non-Steam shortcut: crc32(exe as stored, quotes included, + name),
# high bit set (INT-29).
shortcut_id() { # shortcut_id EXE NAME -> REPLY
  crc32 "$1$2"
  REPLY=$((REPLY | 0x80000000))
}

unquote() { # unquote STRING -> REPLY without one pair of surrounding double quotes
  REPLY=$1
  if [[ ${#REPLY} -ge 2 && $REPLY == \"*\" ]]; then REPLY=${REPLY:1:${#REPLY}-2}; fi
}

# ---- binary VDF (shortcuts.vdf) ----------------------------------------------
# A map is 0x00 name NUL children 0x08, a string 0x01 name NUL value NUL, an int32
# 0x02 name NUL and 4 bytes little-endian; 0x03 float32, 0x07 uint64 and 0x0a int64
# also exist. The file is one map "shortcuts" whose children are the shortcuts, keyed
# "0", "1", ... The reader keeps byte offsets so that output can copy every byte it
# doesn't change from the original file.

H=() N=0 P=0 VDF_ERR=

vdf_fail() { VDF_ERR="$1 at byte $P"; return 1; }

vdf_cstr() { # the NUL-terminated string at P: CS..CE (CE is the NUL); P moves past it
  CS=$P
  while ((P < N)) && [[ ${H[P]} != 00 ]]; do P=$((P + 1)); done
  ((P < N)) || { vdf_fail "unterminated string"; return 1; }
  CE=$P
  P=$((P + 1))
}

vdf_text() { # vdf_text START END -> REPLY, the bytes as text
  local i esc=
  for ((i = $1; i < $2; i++)); do esc+="\\x${H[i]}"; done
  printf -v REPLY '%b' "$esc"
}

vdf_children() { # skips a map's children and its closing 0x08
  while ((P < N)); do
    if [[ ${H[P]} == 08 ]]; then
      P=$((P + 1))
      return 0
    fi
    vdf_item || return 1
  done
  vdf_fail "unterminated map"
}

vdf_item() { # skips the item at P; IT type, NS..NE name, VS..VE value
  local it ns ne vs ve st=$P
  ((P < N)) || { vdf_fail "truncated item"; return 1; }
  it=${H[P]}
  P=$((P + 1))
  vdf_cstr || return 1
  ns=$CS ne=$CE vs=$P
  case $it in
    00) vdf_children || return 1; ve=$P ;;
    01) vdf_cstr || return 1; ve=$CE ;;
    02 | 03 | 04 | 06) ((P + 4 <= N)) || { vdf_fail "truncated value"; return 1; }; P=$((P + 4)); ve=$P ;;
    07 | 0a) ((P + 8 <= N)) || { vdf_fail "truncated value"; return 1; }; P=$((P + 8)); ve=$P ;;
    *) P=$st; vdf_fail "unknown value type 0x$it"; return 1 ;;
  esac
  IT=$it NS=$ns NE=$ne VS=$vs VE=$ve
}

# vdf_parse FILE: reads the file into H and, per child of "shortcuts":
#   E_S..E_E its bytes, E_T its type, E_KS..E_KE its key, E_KEY the key text,
#   for a map also E_EXE, E_NAME, E_APPID ("" when missing) and the byte ranges of its
#   Exe and StartDir items (E_XS..E_XE, E_DS..E_DE, -1 when missing) and the start of
#   its children (E_CS). MAP_END is the 0x08 that closes "shortcuts".
vdf_parse() {
  local s fs lname i
  H=()
  mapfile -t H < <(od -An -v -tx1 -w1 -- "$1")
  H=("${H[@]# }")
  N=${#H[@]} P=0 E_COUNT=0
  E_S=() E_E=() E_T=() E_KS=() E_KE=() E_KEY=() E_CS=()
  E_EXE=() E_NAME=() E_APPID=() E_XS=() E_XE=() E_DS=() E_DE=()
  ((N > 0)) && [[ ${H[0]} == 00 ]] || { vdf_fail "not a binary VDF file"; return 1; }
  P=1
  vdf_cstr || return 1
  vdf_text "$CS" "$CE"
  [[ ${REPLY,,} == shortcuts ]] || { vdf_fail "no shortcuts map"; return 1; }
  while :; do
    ((P < N)) || { vdf_fail "unterminated shortcuts map"; return 1; }
    [[ ${H[P]} == 08 ]] && break
    s=$P
    vdf_item || return 1
    i=$E_COUNT
    E_S[i]=$s E_E[i]=$P E_T[i]=$IT E_KS[i]=$NS E_KE[i]=$NE E_CS[i]=$VS
    vdf_text "$NS" "$NE"
    E_KEY[i]=$REPLY
    E_EXE[i]='' E_NAME[i]='' E_APPID[i]='' E_XS[i]=-1 E_XE[i]=-1 E_DS[i]=-1 E_DE[i]=-1
    if [[ $IT == 00 ]]; then
      P=$VS
      while ((P < N)) && [[ ${H[P]} != 08 ]]; do
        fs=$P
        vdf_item || return 1
        vdf_text "$NS" "$NE"
        lname=${REPLY,,}
        case "$IT:$lname" in
          01:appname) vdf_text "$VS" "$VE"; E_NAME[i]=$REPLY ;;
          01:exe) vdf_text "$VS" "$VE"; E_EXE[i]=$REPLY E_XS[i]=$fs E_XE[i]=$P ;;
          01:startdir) E_DS[i]=$fs E_DE[i]=$P ;;
          02:appid) E_APPID[i]=$((0x${H[VS]} | 0x${H[VS + 1]} << 8 | 0x${H[VS + 2]} << 16 | 0x${H[VS + 3]} << 24)) ;;
        esac
      done
      P=${E_E[i]}
    fi
    E_COUNT=$((E_COUNT + 1))
  done
  MAP_END=$P
  ((P + 1 < N)) && [[ ${H[P + 1]} == 08 ]] || { P=$((P + 1)); vdf_fail "unterminated root"; return 1; }
}

# Escapes for printf '%b': a string with its NUL, an int32, and whole items.
x_str() { # x_str STRING -> REPLY
  local -a bytes=()
  local b out=
  mapfile -t bytes < <(printf '%s' "$1" | od -An -v -tx1 -w1)
  for b in "${bytes[@]}"; do out+="\\x${b# }"; done
  REPLY="$out\\x00"
}
x_int() { # x_int UINT32 -> REPLY
  local v=$1
  printf -v REPLY '\\x%02x\\x%02x\\x%02x\\x%02x' $((v & 255)) $((v >> 8 & 255)) $((v >> 16 & 255)) $((v >> 24 & 255))
}
x_fstr() { # x_fstr NAME VALUE -> REPLY
  local n
  x_str "$1"; n=$REPLY
  x_str "$2"; REPLY="\\x01$n$REPLY"
}
x_fint() { # x_fint NAME UINT32 -> REPLY
  local n
  x_str "$1"; n=$REPLY
  x_int "$2"; REPLY="\\x02$n$REPLY"
}

x_shortcut() { # x_shortcut KEY APPID EXE STARTDIR ICON -> REPLY, a whole shortcut map
  local out
  x_str "$1"; out="\\x00$REPLY"
  x_fint appid "$2"; out+=$REPLY
  x_fstr AppName "$APP_NAME"; out+=$REPLY
  x_fstr Exe "$3"; out+=$REPLY
  x_fstr StartDir "$4"; out+=$REPLY
  x_fstr icon "$5"; out+=$REPLY
  x_fstr ShortcutPath ""; out+=$REPLY
  x_fstr LaunchOptions ""; out+=$REPLY
  x_fint IsHidden 0; out+=$REPLY
  x_fint AllowDesktopConfig 1; out+=$REPLY
  x_fint AllowOverlay 1; out+=$REPLY
  x_fint OpenVR 0; out+=$REPLY
  x_fint Devkit 0; out+=$REPLY
  x_fstr DevkitGameID ""; out+=$REPLY
  x_fint DevkitOverrideAppID 0; out+=$REPLY
  x_fint LastPlayTime 0; out+=$REPLY
  x_fstr FlatpakAppID ""; out+=$REPLY
  x_str tags; out+="\\x00$REPLY\\x08"
  REPLY="$out\\x08"
}

# Edits on the parsed file: replace bytes ED_S..ED_E with ED_X (escapes); an insert has
# ED_S == ED_E. vdf_write SRC DEST writes the file with the edits, copying the rest.
ED_S=() ED_E=() ED_X=()
ed_add() { ED_S+=("$1"); ED_E+=("$2"); ED_X+=("$3"); }

vdf_write() {
  local src=$1 dest=$2 pos=0 i j n=${#ED_S[@]} t
  for ((i = 1; i < n; i++)); do # insertion sort by start; a handful of edits at most
    for ((j = i; j > 0 && ED_S[j - 1] > ED_S[j]; j--)); do
      t=${ED_S[j]}; ED_S[j]=${ED_S[j - 1]}; ED_S[j - 1]=$t
      t=${ED_E[j]}; ED_E[j]=${ED_E[j - 1]}; ED_E[j - 1]=$t
      t=${ED_X[j]}; ED_X[j]=${ED_X[j - 1]}; ED_X[j - 1]=$t
    done
  done
  : >"$dest"
  for ((i = 0; i < n; i++)); do
    copy_bytes "$src" "$pos" "${ED_S[i]}" "$dest"
    printf '%b' "${ED_X[i]}" >>"$dest"
    pos=${ED_E[i]}
  done
  copy_bytes "$src" "$pos" "$N" "$dest"
}

copy_bytes() { # copy_bytes SRC START END DEST: appends SRC's bytes START..END
  (($3 > $2)) || return 0
  dd if="$1" bs=65536 iflag=skip_bytes,count_bytes skip="$2" count="$(($3 - $2))" status=none >>"$4"
}

keys_sequential() { # the shortcuts are keyed 0, 1, 2, ... in order
  local i
  for ((i = 0; i < E_COUNT; i++)); do [[ ${E_KEY[i]} == "$i" ]] || return 1; done
}

# ---- Steam ------------------------------------------------------------------

# STEAM_USERS: userdata/<id> folders, FLATPAK_STEAM: 1 if one is Flatpak's. A folder without
# config/ is an account Steam has not set up (it makes config/ at the first login): it goes
# to NO_CONFIG instead, and gets nothing.
find_steam_users() {
  local r real u id seen=" "
  STEAM_USERS=() NO_CONFIG=() FLATPAK_STEAM=
  for r in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root" \
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
    [[ -d $r/userdata ]] || continue
    real=$(readlink -f -- "$r")
    [[ $seen == *" $real "* ]] && continue
    seen+="$real "
    for u in "$real"/userdata/*/; do
      u=${u%/}
      id=${u##*/}
      [[ $id =~ ^[0-9]+$ && $id != 0 ]] || continue
      if [[ ! -d $u/config ]]; then
        NO_CONFIG+=("$u")
        continue
      fi
      STEAM_USERS+=("$u")
      [[ $real == "$HOME/.var/app/com.valvesoftware.Steam/"* ]] && FLATPAK_STEAM=1
    done
  done
  return 0
}

# Our shortcut: the one whose Exe is the AppImage. An older Anchorage AppImage in
# ~/Applications counts too, and gets its path updated.
find_ours() { # find_ours -> OURS (index or -1), OURS_EXACT (1 when the path is current)
  local i
  OURS=-1 OURS_EXACT=
  for ((i = 0; i < E_COUNT; i++)); do
    [[ ${E_T[i]} == 00 ]] || continue
    unquote "${E_EXE[i]}"
    if [[ $REPLY == "$APPIMAGE" ]]; then OURS=$i OURS_EXACT=1; return 0; fi
  done
  for ((i = 0; i < E_COUNT; i++)); do
    [[ ${E_T[i]} == 00 ]] || continue
    unquote "${E_EXE[i]}"
    if [[ ${REPLY%/*} == "$APPDIR" && ${REPLY##*/} == Anchorage*.AppImage ]]; then OURS=$i; return 0; fi
  done
}

# steam_plan USER: decides what the install changes in USER's shortcuts.vdf. Sets
# PLAN (none, create, add, update, skip), the edits, and SC_ID, the shortcut's ID.
steam_plan() {
  local vdf=$1/config/shortcuts.vdf grid=$1/config/grid exe startdir key i max head
  exe="\"$APPIMAGE\"" startdir="\"$APPDIR\""
  ED_S=() ED_E=() ED_X=() SC_ID=
  file_sig "$vdf"
  PLAN_SIG=$REPLY
  if [[ ! -s $vdf ]]; then
    shortcut_id "$exe" "$APP_NAME"
    SC_ID=$REPLY PLAN=create N=0
    x_str shortcuts
    head="\\x00$REPLY"
    x_shortcut 0 "$SC_ID" "$exe" "$startdir" "$grid/${SC_ID}_icon.png"
    ed_add 0 0 "$head$REPLY\\x08\\x08"
    return 0
  fi
  info "reading the shortcuts of account ${1##*/}"
  if ! vdf_parse "$vdf"; then
    PLAN=skip
    warn "Could not read $vdf ($VDF_ERR). Its shortcut was not added; the file was not changed."
    return 0
  fi
  find_ours
  if ((OURS >= 0)); then
    i=$OURS
    if [[ -n ${E_APPID[i]} ]]; then
      SC_ID=${E_APPID[i]}
    else
      shortcut_id "${E_EXE[i]}" "${E_NAME[i]}"
      SC_ID=$REPLY
      x_fint appid "$SC_ID"
      ed_add "${E_CS[i]}" "${E_CS[i]}" "$REPLY"
    fi
    if [[ -n $OURS_EXACT ]]; then
      PLAN=none
      ((${#ED_S[@]} == 0)) || PLAN=update
      return 0
    fi
    PLAN=update
    x_fstr Exe "$exe"
    ed_add "${E_XS[i]}" "${E_XE[i]}" "$REPLY"
    x_fstr StartDir "$startdir"
    if ((E_DS[i] >= 0)); then
      ed_add "${E_DS[i]}" "${E_DE[i]}" "$REPLY"
    else
      ed_add "${E_XE[i]}" "${E_XE[i]}" "$REPLY"
    fi
    return 0
  fi
  if keys_sequential; then
    key=$E_COUNT
  else
    max=-1
    for ((i = 0; i < E_COUNT; i++)); do
      [[ ${E_KEY[i]} =~ ^[0-9]+$ ]] && ((10#${E_KEY[i]} > max)) && max=$((10#${E_KEY[i]}))
    done
    key=$((max + 1))
  fi
  shortcut_id "$exe" "$APP_NAME"
  SC_ID=$REPLY PLAN=add
  x_shortcut "$key" "$SC_ID" "$exe" "$startdir" "$grid/${SC_ID}_icon.png"
  ed_add "$MAP_END" "$MAP_END" "$REPLY"
}

# steam_unplan USER: the edits that remove our shortcut(s). PLAN none or remove;
# RM_IDS the removed shortcuts' IDs.
steam_unplan() {
  local vdf=$1/config/shortcuts.vdf i k=0 seq='' x
  ED_S=() ED_E=() ED_X=() RM_IDS=() PLAN=none
  file_sig "$vdf"
  PLAN_SIG=$REPLY
  [[ -s $vdf ]] || return 0
  info "reading the shortcuts of account ${1##*/}"
  if ! vdf_parse "$vdf"; then
    PLAN=skip
    warn "Could not read $vdf ($VDF_ERR); it was not changed."
    return 0
  fi
  keys_sequential && seq=1
  for ((i = 0; i < E_COUNT; i++)); do
    if [[ ${E_T[i]} == 00 ]]; then
      unquote "${E_EXE[i]}"
      if [[ $REPLY == "$APPIMAGE" ]]; then
        if [[ -n ${E_APPID[i]} ]]; then
          RM_IDS+=("${E_APPID[i]}")
        else
          shortcut_id "${E_EXE[i]}" "${E_NAME[i]}"
          RM_IDS+=("$REPLY")
        fi
        ed_add "${E_S[i]}" "${E_E[i]}" ""
        continue
      fi
    fi
    if [[ -n $seq && ${E_KEY[i]} != "$k" ]]; then
      x_str "$k"
      x=${REPLY%\\x00}
      ed_add "${E_KS[i]}" "${E_KE[i]}" "$x"
    fi
    k=$((k + 1))
  done
  ((${#RM_IDS[@]} == 0)) || PLAN=remove
}

# The plan steam_plan or steam_unplan made (the edits, N, SC_ID and PLAN) as code for eval,
# so a file that has not changed since (same PLAN_SIG) is not read again: the reader is
# slow (seconds for 1000 shortcuts).
plan_save() { # plan_save -> REPLY
  local arrays
  arrays=$(declare -p ED_S ED_E ED_X)
  printf -v REPLY '%s\nN=%q SC_ID=%q PLAN=%q' "${arrays//declare -a /declare -ga }" "$N" "${SC_ID:-}" "$PLAN"
}

# plan_again USER SIG CODE STEP: the saved plan when USER's shortcuts.vdf still has SIG,
# else the plan made again by STEP (steam_plan or steam_unplan).
plan_again() {
  file_sig "$1/config/shortcuts.vdf"
  if [[ $REPLY == "$2" ]]; then
    eval "$3"
  else
    "$4" "$1"
  fi
}

vdf_commit() { # vdf_commit FILE: writes the planned edits, with a backup; checks the result
  local vdf=$1 new=$1.anchorage-new backup='' old i
  if [[ -e $vdf ]]; then
    backup=$vdf.anchorage-backup-$(date +%Y%m%d-%H%M%S)
    cp -p -- "$vdf" "$backup"
  fi
  NEW=$new
  vdf_write "$vdf" "$new"
  ((N < 65536)) || info "checking the new $vdf"
  if ! vdf_parse "$new"; then
    rm -f -- "$new"
    die "The new $vdf did not read back ($VDF_ERR). The file was not changed."
  fi
  if [[ -n $backup ]]; then chmod --reference="$backup" -- "$new"; fi
  mv -f -- "$new" "$vdf"
  NEW=
  [[ -z $backup ]] || info "backup: $backup"
  # The names sort by time: keep the three newest.
  old=("$vdf".anchorage-backup-*)
  for ((i = 0; i < ${#old[@]} - 3; i++)); do rm -f -- "${old[i]}"; done
}

# ---- release ----------------------------------------------------------------

resolve_release() { # VERSION, TAG
  local want=${OPT_VERSION:-$PINNED_VERSION} url json
  want=${want#v}
  if [[ -n $want ]]; then
    [[ $want =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Not a version: $want (expected X.Y.Z)."
    url=$API/releases/tags/v$want
  else
    url=$API/releases/latest
  fi
  json=$(curl "${CURL_OPTS[@]}" -sS -H 'Accept: application/vnd.github+json' -- "$url") ||
    die "Could not read the release from $url.${want:+ Is $want a released version?}"
  [[ $json =~ \"tag_name\"[[:space:]]*:[[:space:]]*\"v([0-9]+\.[0-9]+\.[0-9]+)\" ]] ||
    die "The release at $url has no vX.Y.Z tag."
  VERSION=${BASH_REMATCH[1]}
  TAG=v$VERSION
  [[ -z $want || $want == "$VERSION" ]] || die "Asked for $want, but the release is $VERSION."
}

read_sums() { # read_sums FILE: SUM[name]=hash
  local hash name
  declare -gA SUM=()
  while read -r hash name; do
    name=${name#\*}
    [[ $hash =~ ^[0-9a-f]{64}$ && -n $name ]] && SUM[$name]=$hash
  done <"$1"
  return 0
}

asset() { # asset NAME -> REPLY: a verified local copy, downloaded once
  local name=$1 dest=$TMP/assets/$1
  if [[ ! -f $dest ]]; then
    mkdir -p -- "$TMP/assets"
    fetch "$DOWNLOADS/$TAG/$name" "$dest" || die "Could not download $name from $DOWNLOADS/$TAG/."
    same_sha "$dest" "${SUM[$name]}" || die "$name does not match the checksum in SHA256SUMS. Nothing was installed from it."
  fi
  REPLY=$dest
}

# ---- install steps ----------------------------------------------------------

desktop_exec() { # desktop_exec PATH -> REPLY, quoted for Exec= (Desktop Entry spec)
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//\`/\\\`}
  s=${s//\$/\\\$}
  s=${s//\\/\\\\}
  s=${s//%/%%}
  REPLY="\"$s\""
}

desktop_entry() { # -> REPLY, the desktop entry's text
  desktop_exec "$APPIMAGE"
  REPLY="[Desktop Entry]
Type=Application
Name=Anchorage
Comment=Install, update and launch the HarbourMasters game ports
Exec=$REPLY
Icon=$APP_ID
StartupWMClass=$APP_ID
Terminal=false
StartupNotify=true
Categories=Game;
$MARKER
"
}

download_appimage() { # download_appimage DEST: downloads the AppImage and checks it
  info "downloading $APPIMAGE_ASSET"
  fetch "$DOWNLOADS/$TAG/$APPIMAGE_ASSET" "$1" progress ||
    die "Could not download $DOWNLOADS/$TAG/$APPIMAGE_ASSET."
  same_sha "$1" "${SUM[$APPIMAGE_ASSET]}" ||
    die "The download does not match the checksum in SHA256SUMS (${SUM[$APPIMAGE_ASSET]}). Nothing was installed."
}

prefetch() { # downloads all the install needs before Steam closes, so it closes only briefly
  local name
  if ! same_sha "$APPIMAGE" "${SUM[$APPIMAGE_ASSET]}"; then
    download_appimage "$TMP/appimage"
    FETCHED=$TMP/appimage
  fi
  same_sha "$ICON" "${SUM[$ICON_ASSET]}" || asset "$ICON_ASSET"
  for name in "${ART_ASSETS[@]}"; do asset "$name"; done
}

install_appimage() {
  local want=${SUM[$APPIMAGE_ASSET]} part=$APPDIR/.Anchorage.AppImage.part
  if same_sha "$APPIMAGE" "$want"; then
    OWN[$APPIMAGE]=$want
    if [[ -x $APPIMAGE ]]; then
      info "$APPIMAGE is already $VERSION"
    else
      CHANGED=1
      [[ -n $DRY ]] && { info "would make $APPIMAGE executable"; return 0; }
      chmod +x -- "$APPIMAGE"
      info "made $APPIMAGE executable"
    fi
    return 0
  fi
  CHANGED=1
  if [[ -n $DRY ]]; then
    info "would download $APPIMAGE_ASSET, check it and install it as $APPIMAGE"
    return 0
  fi
  mkdir -p -- "$APPDIR"
  PART=$part
  if [[ -n $FETCHED ]]; then
    mv -f -- "$FETCHED" "$part"
    FETCHED=
  else
    download_appimage "$part"
  fi
  chmod 755 -- "$part"
  mv -f -- "$part" "$APPIMAGE"
  PART=
  OWN[$APPIMAGE]=$want
  info "installed $APPIMAGE (checksum verified)"
}

install_file() { # install_file SRC DEST LABEL: copies when the content differs
  if [[ -f $2 ]] && cmp -s -- "$1" "$2"; then
    info "$3 is up to date"
    return 0
  fi
  CHANGED=1
  if [[ -n $DRY ]]; then info "would write $2"; return 0; fi
  mkdir -p -- "${2%/*}"
  NEW=$2.anchorage-new
  cp -f -- "$1" "$NEW"
  chmod 644 -- "$NEW"
  mv -f -- "$NEW" "$2"
  NEW=
  info "wrote $2"
}

install_desktop() {
  desktop_entry
  printf '%s' "$REPLY" >"$TMP/desktop"
  install_file "$TMP/desktop" "$DESKTOP" "the desktop entry"
  if same_sha "$ICON" "${SUM[$ICON_ASSET]}"; then
    info "the icon is up to date"
  else
    if [[ -n $DRY ]]; then
      CHANGED=1
      info "would write $ICON"
    else
      asset "$ICON_ASSET"
      install_file "$REPLY" "$ICON" "the icon"
    fi
  fi
  OWN[$ICON]=${SUM[$ICON_ASSET]}
}

# install_art USER ID: the five images, where they differ. An image that is neither the
# release's nor the one this script wrote before is the user's (set in Steam): kept.
art_state() { # art_state DEST HASH -> REPLY: same, kept (an image the user set) or write
  if same_sha "$1" "$2"; then
    REPLY=same
  elif [[ -e $1 ]] && ! { [[ -n ${OWN[$1]:-} ]] && same_sha "$1" "${OWN[$1]}"; }; then
    REPLY=kept
  else
    REPLY="write"
  fi
}

art_pending() { # art_pending USER ID: install_art would write some of the images
  local i
  for i in "${!ART_ASSETS[@]}"; do
    art_state "$1/config/grid/$2${ART_SUFFIXES[i]}.png" "${SUM[${ART_ASSETS[i]}]}"
    [[ $REPLY != write ]] || return 0
  done
  return 1
}

install_art() {
  local grid=$1/config/grid i name dest want n=0
  for i in "${!ART_ASSETS[@]}"; do
    name=${ART_ASSETS[i]} want=${SUM[${ART_ASSETS[i]}]}
    dest=$grid/$2${ART_SUFFIXES[i]}.png
    art_state "$dest" "$want"
    case $REPLY in
      same)
        OWN[$dest]=$want
        continue
        ;;
      kept)
        unset 'OWN[$dest]'
        info "account ${1##*/}: kept $dest: this script did not write it (set in Steam?)"
        continue
        ;;
    esac
    CHANGED=1 n=$((n + 1))
    [[ -z $DRY ]] || continue
    asset "$name"
    mkdir -p -- "$grid"
    cp -f -- "$REPLY" "$dest"
    chmod 644 -- "$dest"
    OWN[$dest]=$want
  done
  if ((n == 0)); then
    info "account ${1##*/}: artwork up to date"
  elif [[ -n $DRY ]]; then
    info "account ${1##*/}: would write $n artwork images as $grid/$2*.png"
  else
    info "account ${1##*/}: wrote $n artwork images as $grid/$2*.png"
  fi
}

do_install() {
  local u i art_missing extra users_planned=() plans=() ids=() sigs=() saved=() write=
  step "Finding the release"
  resolve_release
  APPIMAGE_ASSET=Anchorage-$VERSION-x86_64.AppImage
  info "Anchorage $VERSION ($TAG)"
  fetch "$DOWNLOADS/$TAG/SHA256SUMS" "$TMP/SHA256SUMS" ||
    die "Could not download $DOWNLOADS/$TAG/SHA256SUMS. Releases before the installer don't have one: pick a newer one with --version."
  read_sums "$TMP/SHA256SUMS"
  [[ -n ${SUM[$APPIMAGE_ASSET]:-} ]] || die "SHA256SUMS has no line for $APPIMAGE_ASSET."
  art_missing=
  for i in "${ART_ASSETS[@]}" "$ICON_ASSET"; do [[ -n ${SUM[$i]:-} ]] || art_missing+=" $i"; done
  [[ -z $art_missing ]] || die "SHA256SUMS lists no${art_missing}."

  step "Checking Steam"
  find_steam_users
  note_no_config
  if ((${#STEAM_USERS[@]} == 0)); then
    info "no Steam accounts found (looked in ~/.local/share/Steam, ~/.steam and Flatpak Steam)"
  fi
  for u in "${STEAM_USERS[@]}"; do
    steam_plan "$u"
    users_planned+=("$u")
    plans+=("$PLAN")
    ids+=("${SC_ID:-}")
    sigs+=("$PLAN_SIG")
    plan_save
    saved+=("$REPLY")
    extra=
    case $PLAN in
      create | add | update) write=1 ;;
      none) if art_pending "$u" "$SC_ID"; then write=1 extra=", artwork to write"; fi ;;
    esac
    info "account ${u##*/}: $(plan_text "$PLAN")$extra"
  done
  [[ -z $write ]] || steam_check
  if [[ -n $STEAM_CLOSE && -z $DRY ]]; then
    step "Downloading Anchorage $VERSION"
    prefetch
    steam_close
  fi

  step "Installing Anchorage $VERSION"
  install_appimage
  install_desktop
  own_save

  step "Adding the Steam shortcut"
  ((${#users_planned[@]} > 0)) || info "skipped: no Steam accounts"
  for i in "${!users_planned[@]}"; do
    u=${users_planned[i]}
    [[ ${plans[i]} != skip ]] || { FAILED=1; continue; }
    if [[ ${plans[i]} != none ]]; then
      CHANGED=1
      if [[ -n $DRY ]]; then
        info "account ${u##*/}: would ${plans[i]} the shortcut in $u/config/shortcuts.vdf"
      else
        if steam_running; then
          die "Steam was started while Anchorage was being installed, so the shortcut was not added.
Exit Steam, then run the same command again: it only adds what is missing."
        fi
        plan_again "$u" "${sigs[i]}" "${saved[i]}" steam_plan
        vdf_commit "$u/config/shortcuts.vdf"
        case ${plans[i]} in
          update) info "account ${u##*/}: shortcut updated" ;;
          *) info "account ${u##*/}: shortcut added" ;;
        esac
      fi
    fi
    install_art "$u" "${ids[i]}"
    own_save
  done
  if [[ -n $FLATPAK_STEAM ]]; then
    info "Flatpak Steam can only start the AppImage once it may read ~/Applications:"
    info "  flatpak override --user --filesystem=~/Applications com.valvesoftware.Steam"
  fi

  steam_restart

  if [[ -n $DRY ]]; then
    say ""
    say "Dry run: nothing was changed."
  elif [[ -z $CHANGED ]]; then
    say ""
    say "Anchorage $VERSION is already installed. Nothing to do."
  else
    say ""
    say "Anchorage $VERSION is installed: $APPIMAGE"
    if [[ -n $RESTARTED ]]; then
      say "Steam is starting again. Anchorage is in the library, under Non-Steam."
    elif ((${#users_planned[@]} > 0)); then
      say "Start Steam (or return to Gaming Mode): Anchorage is in the library, under Non-Steam."
    fi
  fi
}

plan_text() {
  case $1 in
    none) REPLY="shortcut already there" ;;
    create) REPLY="will create shortcuts.vdf with the shortcut" ;;
    add) REPLY="will add the shortcut" ;;
    update) REPLY="will update the shortcut's path" ;;
    remove) REPLY="will remove the shortcut" ;;
    skip) REPLY="skipped (shortcuts.vdf could not be read)" ;;
  esac
  printf '%s' "$REPLY"
}

do_uninstall() {
  local u i id suf write='' users_planned=() plans=() idlists=() rm_ids=() sigs=() saved=()
  step "Checking Steam"
  find_steam_users
  note_no_config
  for u in "${STEAM_USERS[@]}"; do
    steam_unplan "$u"
    users_planned+=("$u")
    plans+=("$PLAN")
    idlists+=("${RM_IDS[*]:-}")
    sigs+=("$PLAN_SIG")
    plan_save
    saved+=("$REPLY")
    [[ $PLAN != remove ]] || write=1
    if [[ $PLAN == none ]]; then
      info "account ${u##*/}: no Anchorage shortcut"
    else
      info "account ${u##*/}: $(plan_text "$PLAN")"
    fi
  done
  [[ -z $write ]] || steam_check
  [[ -z $STEAM_CLOSE || -n $DRY ]] || steam_close

  step "Removing Anchorage"
  for i in "${!users_planned[@]}"; do
    u=${users_planned[i]}
    [[ ${plans[i]} != skip ]] || { FAILED=1; continue; }
    if [[ ${plans[i]} == remove ]]; then
      CHANGED=1
      if [[ -n $DRY ]]; then
        info "account ${u##*/}: would remove the shortcut from $u/config/shortcuts.vdf"
      else
        steam_running && die "Steam was started during the uninstall. Exit Steam, then run it again."
        plan_again "$u" "${sigs[i]}" "${saved[i]}" steam_unplan
        vdf_commit "$u/config/shortcuts.vdf"
        info "account ${u##*/}: shortcut removed"
      fi
    fi
    read -ra rm_ids <<<"${idlists[i]}"
    for id in "${rm_ids[@]}"; do
      for suf in "${ART_SUFFIXES[@]}"; do
        QUIET=1 remove_own "$u/config/grid/$id$suf.png"
      done
      if [[ -n $DRY ]]; then
        info "account ${u##*/}: would remove the artwork it wrote, $u/config/grid/$id*.png"
      else
        info "account ${u##*/}: removed the artwork it wrote, $u/config/grid/$id*.png"
      fi
    done
  done
  remove_own "$APPIMAGE"
  if [[ -f $DESKTOP ]] && grep -qxF -- "$MARKER" "$DESKTOP"; then
    remove_file "$DESKTOP"
  elif [[ -f $DESKTOP ]]; then
    info "kept $DESKTOP: this script did not write it"
  fi
  remove_own "$ICON"
  own_save
  steam_restart
  say ""
  if [[ -n $DRY ]]; then
    say "Dry run: nothing was changed."
  elif [[ -z $CHANGED ]]; then
    say "Anchorage was not installed by this script. Nothing to do."
  else
    say "Anchorage is removed. Its own data is still there; delete these folders to remove it too:"
    say "  ${XDG_DATA_HOME:-$HOME/.local/share}/anchorage (installed ports)"
    say "  ${XDG_CONFIG_HOME:-$HOME/.config}/anchorage (settings)"
    say "  ${XDG_STATE_HOME:-$HOME/.local/state}/anchorage and ${XDG_CACHE_HOME:-$HOME/.cache}/anchorage"
  fi
}

remove_file() {
  [[ -e $1 || -L $1 ]] || return 0
  CHANGED=1
  if [[ -n $DRY ]]; then [[ -n ${QUIET:-} ]] || info "would remove $1"; return 0; fi
  rm -f -- "$1"
  [[ -n ${QUIET:-} ]] || info "removed $1"
}

# remove_own PATH: removes it only while it is the file this script wrote (OWN).
remove_own() {
  if [[ -e $1 || -L $1 ]]; then
    if [[ -n ${OWN[$1]:-} ]] && same_sha "$1" "${OWN[$1]}"; then
      remove_file "$1"
    else
      info "kept $1: this script did not write it"
    fi
  fi
  unset 'OWN[$1]'
}

note_no_config() {
  local u
  for u in "${NO_CONFIG[@]}"; do
    info "account ${u##*/}: skipped (no config folder: Steam has not set this account up)"
  done
}

# ---- the files this script wrote (INT-33) -----------------------------------
# MANIFEST lists them as sha256sum does (hash, two spaces, path), with the hash they had
# when written: only those are replaced (artwork) or removed (--uninstall).

own_load() {
  local hash path
  declare -gA OWN=()
  [[ -f $MANIFEST ]] || return 0
  while read -r hash path; do
    [[ $hash =~ ^[0-9a-f]{64}$ && $path == /* ]] && OWN[$path]=$hash
  done <"$MANIFEST"
  return 0
}

own_save() { # writes MANIFEST from OWN when it differs; removes it when OWN is empty
  local p text=''
  local -a paths=()
  [[ -z $DRY ]] || return 0
  if ((${#OWN[@]} == 0)); then
    [[ ! -e $MANIFEST ]] || rm -f -- "$MANIFEST"
    rmdir -- "${MANIFEST%/*}" 2>/dev/null || true
    return 0
  fi
  mapfile -t paths < <(printf '%s\n' "${!OWN[@]}" | sort)
  for p in "${paths[@]}"; do text+="${OWN[$p]}  $p"$'\n'; done
  printf '%s' "$text" >"$TMP/files.sha256"
  [[ -f $MANIFEST ]] && cmp -s -- "$TMP/files.sha256" "$MANIFEST" && return 0
  mkdir -p -- "${MANIFEST%/*}"
  NEW=$MANIFEST.anchorage-new
  cp -f -- "$TMP/files.sha256" "$NEW"
  mv -f -- "$NEW" "$MANIFEST"
  NEW=
}

cleanup() {
  steam_restart
  [[ -z ${PART:-} ]] || rm -f -- "$PART"
  [[ -z ${NEW:-} ]] || rm -f -- "$NEW"
  [[ -z ${TMP:-} ]] || rm -rf -- "$TMP"
}

main() {
  # Under `curl | bash`, bash reads this script from standard input: nothing else may.
  exec </dev/null
  local mode=install t
  OPT_VERSION='' DRY='' CHANGED='' FAILED='' PART='' NEW='' TMP='' FETCHED=''
  NO_RESTART='' STEAM_CLOSE='' STEAM_CLOSED=() RESTARTED=''
  COUNTDOWN=${ANCHORAGE_COUNTDOWN:-5} STEAM_WAIT=${ANCHORAGE_STEAM_WAIT:-60}
  [[ $COUNTDOWN =~ ^[0-9]+$ ]] || COUNTDOWN=5
  [[ $STEAM_WAIT =~ ^[0-9]+$ ]] || STEAM_WAIT=60
  while (($# > 0)); do
    case $1 in
      --version) (($# >= 2)) || die "--version needs a version, like --version 1.2.0"; OPT_VERSION=$2; shift ;;
      --version=*) OPT_VERSION=${1#*=} ;;
      --dry-run) DRY=1 ;;
      --uninstall) mode=uninstall ;;
      --no-steam-restart) NO_RESTART=1 ;;
      -h | --help) usage; return 0 ;;
      *) usage >&2; exit 2 ;;
    esac
    shift
  done
  : "${HOME:?HOME is not set}"
  [[ $HOME == / ]] || HOME=${HOME%/}
  [[ $(id -u) != 0 ]] || die "Run this as your own user (deck on a Steam Deck), not as root."
  for t in od dd sha256sum mktemp readlink cmp grep stat sort; do
    command -v "$t" >/dev/null 2>&1 || die "This needs $t, which is missing."
  done
  if [[ $mode == install ]]; then
    command -v curl >/dev/null 2>&1 || die "This needs curl, which is missing."
    [[ $(uname -m) == x86_64 ]] || die "The Anchorage AppImage is for x86_64; this is $(uname -m)."
  fi
  APPDIR=$HOME/Applications
  APPIMAGE=$APPDIR/Anchorage.AppImage
  DATA=${XDG_DATA_HOME:-$HOME/.local/share}
  DESKTOP=$DATA/applications/$APP_ID.desktop
  ICON=$DATA/icons/hicolor/scalable/apps/$APP_ID.svg
  STATE=${XDG_STATE_HOME:-$HOME/.local/state}
  [[ $STATE == /* ]] || STATE=$HOME/.local/state
  MANIFEST=$STATE/anchorage-installer/files.sha256
  [[ $APPIMAGE != *$'\n'* ]] || die "HOME contains a newline."
  TMP=$(mktemp -d)
  trap cleanup EXIT
  own_load
  [[ -z $DRY ]] || say "Dry run: nothing will be changed."
  if [[ $mode == uninstall ]]; then do_uninstall; else do_install; fi
  [[ -z $FAILED ]] || die "Some Steam accounts were skipped (see the warnings above)."
}

main "$@"
