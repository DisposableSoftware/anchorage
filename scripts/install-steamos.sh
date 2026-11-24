#!/usr/bin/env bash
# Installs Anchorage on SteamOS from Desktop Mode, or on any x86_64 Linux with Steam:
#
#   curl -fsSL https://raw.githubusercontent.com/DisposableSoftware/anchorage/main/scripts/install-steamos.sh | bash
#
# It downloads the release AppImage to ~/Applications/Anchorage.AppImage, checks it
# against the release's SHA256SUMS, adds a desktop entry and icon, and adds an
# "Anchorage" shortcut with artwork to every Steam account (Steam must be closed).
# Spec: INT-28, INT-29, INT-33, INT-34 in spec/integration.md, with the reasons.
#
# Options (through curl: ... | bash -s -- --uninstall):
#   --version X.Y.Z   install that release instead of the latest
#   --dry-run         say what would change, change nothing
#   --uninstall       remove what this script added (not Anchorage's own data)
#   --help
#
# Needs bash, curl and coreutils. It reads nothing from standard input.
# For tests only: ANCHORAGE_API_URL and ANCHORAGE_DOWNLOAD_BASE replace the GitHub URLs.
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
Usage: install-steamos.sh [--version X.Y.Z] [--dry-run] [--uninstall]
       curl -fsSL https://raw.githubusercontent.com/DisposableSoftware/anchorage/main/scripts/install-steamos.sh | bash -s -- [options]
EOF
}

# ---- small helpers ----------------------------------------------------------

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

fetch() { # fetch URL DEST [progress]
  local -a opts=(-fL --retry 3 --connect-timeout 20 -o "$2")
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

steam_closed_or_die() {
  steam_running || return 0
  die "Steam is running. Steam rewrites its shortcuts file when it exits, so the shortcut
can't be changed now. Nothing was changed.
Exit Steam first: in Desktop Mode, right-click the Steam icon in the system tray and
choose Exit (or run: steam -shutdown). When it has closed, run the same command again."
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

find_steam_users() { # STEAM_USERS: userdata/<id> folders, FLATPAK_STEAM: 1 if one is Flatpak's
  local r real u id seen=" "
  STEAM_USERS=() FLATPAK_STEAM=
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
  if [[ ! -s $vdf ]]; then
    shortcut_id "$exe" "$APP_NAME"
    SC_ID=$REPLY PLAN=create N=0
    x_str shortcuts
    head="\\x00$REPLY"
    x_shortcut 0 "$SC_ID" "$exe" "$startdir" "$grid/${SC_ID}_icon.png"
    ed_add 0 0 "$head$REPLY\\x08\\x08"
    return 0
  fi
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
  [[ -s $vdf ]] || return 0
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

vdf_commit() { # vdf_commit FILE: writes the planned edits, with a backup; checks the result
  local vdf=$1 new=$1.anchorage-new backup=
  if [[ -e $vdf ]]; then
    backup=$vdf.anchorage-backup-$(date +%Y%m%d-%H%M%S)
    cp -p -- "$vdf" "$backup"
  fi
  vdf_write "$vdf" "$new"
  if ! vdf_parse "$new"; then
    rm -f -- "$new"
    die "The new $vdf did not read back ($VDF_ERR). The file was not changed."
  fi
  if [[ -n $backup ]]; then chmod --reference="$backup" -- "$new"; fi
  mv -f -- "$new" "$vdf"
  [[ -z $backup ]] || info "backup: $backup"
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
  json=$(curl -fsSL --retry 3 --connect-timeout 20 -H 'Accept: application/vnd.github+json' -- "$url") ||
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

install_appimage() {
  local want=${SUM[$APPIMAGE_ASSET]} part=$APPDIR/.Anchorage.AppImage.part
  if same_sha "$APPIMAGE" "$want"; then
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
  info "downloading $APPIMAGE_ASSET"
  fetch "$DOWNLOADS/$TAG/$APPIMAGE_ASSET" "$part" progress ||
    die "Could not download $DOWNLOADS/$TAG/$APPIMAGE_ASSET."
  same_sha "$part" "$want" ||
    die "The download does not match the checksum in SHA256SUMS ($want). Nothing was installed."
  chmod 755 -- "$part"
  mv -f -- "$part" "$APPIMAGE"
  PART=
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
  cp -f -- "$1" "$2.anchorage-new"
  chmod 644 -- "$2.anchorage-new"
  mv -f -- "$2.anchorage-new" "$2"
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
}

install_art() { # install_art USER ID: the five images, where they differ
  local grid=$1/config/grid i name dest n=0
  for i in "${!ART_ASSETS[@]}"; do
    name=${ART_ASSETS[i]}
    dest=$grid/$2${ART_SUFFIXES[i]}.png
    same_sha "$dest" "${SUM[$name]}" && continue
    CHANGED=1 n=$((n + 1))
    [[ -z $DRY ]] || continue
    asset "$name"
    mkdir -p -- "$grid"
    cp -f -- "$REPLY" "$dest"
    chmod 644 -- "$dest"
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
  local u i art_missing users_planned=() plans=() ids=() write=
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
  if ((${#STEAM_USERS[@]} == 0)); then
    info "no Steam accounts found (looked in ~/.local/share/Steam, ~/.steam and Flatpak Steam)"
  fi
  for u in "${STEAM_USERS[@]}"; do
    steam_plan "$u"
    users_planned+=("$u")
    plans+=("$PLAN")
    ids+=("${SC_ID:-}")
    case $PLAN in
      create | add | update) write=1 ;;
    esac
    info "account ${u##*/}: $(plan_text "$PLAN")"
  done
  [[ -z $write ]] || steam_closed_or_die

  step "Installing Anchorage $VERSION"
  install_appimage
  install_desktop

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
        steam_plan "$u" # the same plan again: H and the edits belong to the last user parsed
        vdf_commit "$u/config/shortcuts.vdf"
        case ${plans[i]} in
          update) info "account ${u##*/}: shortcut updated" ;;
          *) info "account ${u##*/}: shortcut added" ;;
        esac
      fi
    fi
    install_art "$u" "${ids[i]}"
  done
  if [[ -n $FLATPAK_STEAM ]]; then
    info "Flatpak Steam can only start the AppImage once it may read ~/Applications:"
    info "  flatpak override --user --filesystem=~/Applications com.valvesoftware.Steam"
  fi

  if [[ -n $DRY ]]; then
    say ""
    say "Dry run: nothing was changed."
  elif [[ -z $CHANGED ]]; then
    say ""
    say "Anchorage $VERSION is already installed. Nothing to do."
  else
    say ""
    say "Anchorage $VERSION is installed: $APPIMAGE"
    ((${#users_planned[@]} == 0)) ||
      say "Start Steam (or return to Gaming Mode): Anchorage is in the library, under Non-Steam."
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
  local u i id suf write='' users_planned=() plans=() idlists=() rm_ids=()
  step "Checking Steam"
  find_steam_users
  for u in "${STEAM_USERS[@]}"; do
    steam_unplan "$u"
    users_planned+=("$u")
    plans+=("$PLAN")
    idlists+=("${RM_IDS[*]:-}")
    [[ $PLAN != remove ]] || write=1
    if [[ $PLAN == none ]]; then
      info "account ${u##*/}: no Anchorage shortcut"
    else
      info "account ${u##*/}: $(plan_text "$PLAN")"
    fi
  done
  [[ -z $write ]] || steam_closed_or_die

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
        steam_unplan "$u"
        vdf_commit "$u/config/shortcuts.vdf"
        info "account ${u##*/}: shortcut removed"
      fi
    fi
    read -ra rm_ids <<<"${idlists[i]}"
    for id in "${rm_ids[@]}"; do
      for suf in "${ART_SUFFIXES[@]}"; do
        QUIET=1 remove_file "$u/config/grid/$id$suf.png"
      done
      if [[ -n $DRY ]]; then
        info "account ${u##*/}: would remove the artwork $u/config/grid/$id*.png"
      else
        info "account ${u##*/}: removed the artwork $u/config/grid/$id*.png"
      fi
    done
  done
  remove_file "$APPIMAGE"
  if [[ -f $DESKTOP ]] && grep -qxF -- "$MARKER" "$DESKTOP"; then
    remove_file "$DESKTOP"
  elif [[ -f $DESKTOP ]]; then
    info "kept $DESKTOP: this script did not write it"
  fi
  remove_file "$ICON"
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

cleanup() {
  [[ -z ${PART:-} ]] || rm -f -- "$PART"
  [[ -z ${TMP:-} ]] || rm -rf -- "$TMP"
}

main() {
  # Under `curl | bash`, bash reads this script from standard input: nothing else may.
  exec </dev/null
  local mode=install t
  OPT_VERSION='' DRY='' CHANGED='' FAILED='' PART='' TMP=''
  while (($# > 0)); do
    case $1 in
      --version) (($# >= 2)) || die "--version needs a version, like --version 1.2.0"; OPT_VERSION=$2; shift ;;
      --version=*) OPT_VERSION=${1#*=} ;;
      --dry-run) DRY=1 ;;
      --uninstall) mode=uninstall ;;
      -h | --help) usage; return 0 ;;
      *) usage >&2; exit 2 ;;
    esac
    shift
  done
  : "${HOME:?HOME is not set}"
  [[ $HOME == / ]] || HOME=${HOME%/}
  [[ $(id -u) != 0 ]] || die "Run this as your own user (deck on a Steam Deck), not as root."
  for t in od dd sha256sum mktemp readlink cmp grep; do
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
  [[ $APPIMAGE != *$'\n'* ]] || die "HOME contains a newline."
  TMP=$(mktemp -d)
  trap cleanup EXIT
  [[ -z $DRY ]] || say "Dry run: nothing will be changed."
  if [[ $mode == uninstall ]]; then do_uninstall; else do_install; fi
  [[ -z $FAILED ]] || die "Some Steam accounts were skipped (see the warnings above)."
}

main "$@"
