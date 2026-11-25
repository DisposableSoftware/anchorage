#! /usr/bin/env nix-shell
#! nix-shell -i bash -p "python3.withPackages (ps: [ ps.vdf ])" shellcheck curl desktop-file-utils util-linux godot
# shellcheck shell=bash
# Spec: INT-28, INT-29, INT-33, INT-34, INT-35, UPD-7.
# Runs scripts/install-steamos.sh the way `curl ... | bash` does, against fake HOME and
# Steam folders, a fake GitHub API and fake release assets served from 127.0.0.1, and a
# fake Steam (steam, flatpak and pgrep commands first in PATH) that runs, quits after
# -shutdown or never, and logs each call. The results are read back with an independent
# VDF parser (ValvePython's vdf, scripts/manual/steam-install/check.py) and compared
# byte for byte with the files before. Nothing outside a temp dir is touched, and no real
# Steam, release or network is used. Also runs shellcheck on the scripts. A self-update
# (UPD-7) is made by the app's own code (godot runs app/tests/self_update_swap.gd).
# Usage: scripts/manual/steam-install.sh   (KEEP=1 keeps the temp dir)
# `nix flake check` runs it as checks.x86_64-linux.steam-install.
set -euo pipefail
cd "$(dirname "$0")/../.."
REPO=$PWD
HERE=$REPO/scripts/manual/steam-install
ID=io.github.DisposableSoftware.Anchorage
T=$(mktemp -d)
SRV_PID=
harness_cleanup() {
  [[ -z $SRV_PID ]] || kill "$SRV_PID" 2>/dev/null || true
  if [[ -n ${KEEP:-} ]]; then echo "kept $T"; else rm -rf "$T"; fi
}
trap harness_cleanup EXIT

PASS=0
ok() { PASS=$((PASS + 1)); echo "ok - $*"; }
fail() { echo "FAIL - $*" >&2; [[ -f ${LOG:-} ]] && sed 's/^/    | /' "$LOG" >&2; exit 1; }
py() { python3 -I "$@"; }
check() { py "$HERE/check.py" "$@" >/dev/null || fail "check.py $*"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
tree_state() { # every path, type, size, mode, and each file's mtime and hash
  (cd "$1" && find . -printf '%p %y %s %m\n' | sort && find . -type f -printf '%p %T@\n' | sort &&
    find . -type f -exec sha256sum {} + | sort)
}

echo "# shellcheck"
shellcheck -x scripts/install-steamos.sh scripts/release-assets.sh scripts/manual/steam-install.sh ||
  fail shellcheck
ok "shellcheck is clean"

echo "# Steam's shortcut ID (INT-29)"
(
# The installer's own functions, without running main, in a subshell of their own.
# shellcheck source=/dev/null
source <(sed '/^main "\$@"$/d' scripts/install-steamos.sh)
crc32 "123456789"
[[ $REPLY == 3421780262 ]] || fail "crc32 check value: $REPLY"
# Vectors from shortcuts.vdf files Steam ROM Manager wrote (steam_shortcuts_util
# testdata/steam_rom_manager.vdf): Exe exactly as stored, AppName, appid.
amazon='"C:\Users\Philip\AppData\local\Amazon Games\App\Amazon Games.exe"'
while IFS='|' read -r exe name want; do
  shortcut_id "$exe" "$name"
  [[ $REPLY == "$want" ]] || fail "shortcut_id $exe $name: $REPLY, expected $want"
done <<EOF
D:\\\\Itch\\\\oddrealm\\oddrealm_v0_10_0_21_win/OddRealm.exe|Odd Realm|4012838840
$amazon|Turnip Boy Commits Tax Evasion|2862000526
$amazon|Galaxy of Pen and Paper|3953171138
$amazon|The Curse of Monkey Island|2634833882
EOF
for s in "/home/deck/Applications/Anchorage.AppImage" 'Pokémon "Snap" \ 日本語' ""; do
  shortcut_id "\"$s\"" Anchorage
  want=$(py "$HERE/check.py" appid "\"$s\"" Anchorage)
  [[ $REPLY == "$want" ]] || fail "shortcut_id for $s: $REPLY, zlib says $want"
done
) || exit 1
ok "shortcut IDs match Steam ROM Manager's and zlib's"

echo "# fake releases"
SRV=$T/srv
mkdir -p "$SRV/api/releases/tags" "$SRV/raw"
release() { # release VERSION: a fake AppImage and the real release assets for it
  head -c $((300000 + ${1//./})) /dev/urandom >"$T/fake-$1.AppImage"
  bash scripts/release-assets.sh "$1" "$T/fake-$1.AppImage" "$SRV/download/v$1" >/dev/null
  printf '{\n  "url": "x",\n  "tag_name": "v%s",\n  "name": "Anchorage %s"\n}\n' "$1" "$1" >"$SRV/api/releases/tags/v$1"
}
latest() { cp "$SRV/api/releases/tags/v$1" "$SRV/api/releases/latest"; }
release 1.2.0
release 1.3.0
release 6.6.6
sed -i "1s/^[0-9a-f]*/$(printf '0%.0s' {1..64})/" "$SRV/download/v6.6.6/SHA256SUMS"
latest 1.2.0
cp scripts/install-steamos.sh "$SRV/raw/install-steamos.sh"
grep -qx 'PINNED_VERSION="1.2.0"' "$SRV/download/v1.2.0/install-steamos.sh" || fail "release copy is not pinned"
(cd "$SRV/download/v1.2.0" && sha256sum -c --quiet SHA256SUMS) || fail "release SHA256SUMS"
ok "release-assets.sh stages the AppImage, art, icon, pinned script and SHA256SUMS"

python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$SRV" >"$T/server.log" 2>&1 &
SRV_PID=$!
for _ in $(seq 50); do
  PORT=$(sed -n 's/.* port \([0-9]*\) .*/\1/p' "$T/server.log" | head -1)
  [[ -n $PORT ]] && break
  sleep 0.1
done
[[ -n $PORT ]] || fail "the test server did not start"
URL=http://127.0.0.1:$PORT

# Fake Steam (INT-35): native Steam runs while $S/native exists, Flatpak Steam while
# $S/flatpak does. pgrep -x steam sees both (the host sees Flatpak's steam process too),
# flatpak ps lists the Flatpak one. `steam -shutdown` (or `flatpak run
# com.valvesoftware.Steam -shutdown`) returns at once and Steam exits 3 s later (after the 2 s
# the installer waits once Steam is gone, so an edit that did not wait shows), or
# never when $S/mode says stuck; any other call starts it. Each call goes to $S/log with
# the hash of the file named in $S/watch, the display it got and whether it runs in a
# session of its own (detached from the terminal). These come first in PATH, so a real
# Steam on the machine is never called.
S=$T/steam
mkdir -p "$T/bin" "$T/tmp" "$S"
cat >"$T/bin/fake-steam" <<'EOF'
#!/bin/sh
S=@S@
kind=$1
shift
hash() {
  w=$(cat "$S/watch" 2>/dev/null)
  if [ -n "$w" ] && [ -f "$w" ]; then sha256sum "$w" | cut -c1-16; else echo none; fi
}
if [ "$1" = -shutdown ]; then
  echo "$kind shutdown $(hash)" >>"$S/log"
  [ -e "$S/$kind" ] || exit 0
  [ "$(cat "$S/mode" 2>/dev/null)" = stuck ] && exit 0
  (sleep 3; echo "$kind exited $(hash)" >>"$S/log"; rm -f "$S/$kind") &
  exit 0
fi
detached=no
[ "$(cut -d' ' -f6 /proc/$$/stat)" = "$$" ] && detached=yes
echo "$kind start $* $(hash) display=${DISPLAY:-}/${WAYLAND_DISPLAY:-} detached=$detached" >>"$S/log"
touch "$S/$kind"
EOF
cat >"$T/bin/steam" <<'EOF'
#!/bin/sh
exec @S@/../bin/fake-steam native "$@"
EOF
cat >"$T/bin/flatpak" <<'EOF'
#!/bin/sh
case "$1" in
  ps) [ "$2" = --columns=application ] && [ -e @S@/flatpak ] && echo com.valvesoftware.Steam; exit 0 ;;
  run) [ "$2" = com.valvesoftware.Steam ] || exit 1; shift 2; exec @S@/../bin/fake-steam flatpak "$@" ;;
esac
exit 1
EOF
cat >"$T/bin/pgrep" <<'EOF'
#!/bin/sh
[ "$*" = "-x steam" ] && { [ -e @S@/native ] || [ -e @S@/flatpak ]; }
EOF
sed -i "s|@S@|$S|g" "$T/bin/fake-steam" "$T/bin/steam" "$T/bin/flatpak" "$T/bin/pgrep"
chmod +x "$T/bin/fake-steam" "$T/bin/steam" "$T/bin/flatpak" "$T/bin/pgrep"
BASE_PATH=$T/bin:$PATH
steam_on() { # steam_on KIND [MODE] [WATCH]: a fresh log, that Steam running
  rm -f "$S/log" "$S/native" "$S/flatpak" "$S/watch"
  echo "${2:-exits}" >"$S/mode"
  [[ -z ${3:-} ]] || echo "$3" >"$S/watch"
  touch "$S/$1"
}
steam_off() { rm -f "$S/log" "$S/native" "$S/flatpak" "$S/watch" "$S/mode"; }
starts() { grep -c ' start ' "$S/log" 2>/dev/null || true; }
log_wait() { # log_wait PATTERN: the fake Steam's log gets the line within 3 s (setsid -f returns first)
  local _
  for _ in $(seq 30); do
    grep -q -- "$1" "$S/log" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}
no_steam_calls() { # nothing called the fake Steam (a late detached start included)
  sleep 0.3
  [[ ! -e $S/log ]] || fail "$1: Steam was called: $(cat "$S/log")"
}
DESKTOP_ENV=(DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 ANCHORAGE_COUNTDOWN=0)
RUN_ENV=() XENV=()

# run NAME HOME [ARGS...]: pipes the script from the fake raw URL into bash, as the
# README's command does. SCRIPT_URL picks another copy; RUN_ENV adds variables.
run() {
  local name=$1 home=$2
  shift 2
  LOG=$T/$name.log
  set +e
  # shellcheck disable=SC2016 # expanded by the inner bash
  env -i HOME="$home" PATH="$BASE_PATH" LANG=C.UTF-8 TMPDIR="$T/tmp" "${RUN_ENV[@]}" \
    ANCHORAGE_API_URL="$URL/api" ANCHORAGE_DOWNLOAD_BASE="$URL/download" \
    bash -c 'curl -fsSL "$1" | bash -s -- "${@:2}"' _ "${SCRIPT_URL:-$URL/raw/install-steamos.sh}" "$@" >"$LOG" 2>&1
  STATUS=$?
  set -e
}
drun() { # drun NAME HOME [ARGS...]: run in a desktop session (DESKTOP_ENV), plus XENV
  RUN_ENV=("${DESKTOP_ENV[@]}" "${XENV[@]}")
  run "$@"
  RUN_ENV=()
}
expect_ok() { [[ $STATUS == 0 ]] || fail "$1: exit $STATUS"; }
expect_fail() { [[ $STATUS != 0 ]] || fail "$1: exit 0, expected a failure"; grep -q -- "$2" "$LOG" || fail "$1: no \"$2\" in the output"; }
art() { echo "$SRV/download/v$1"; }

steam_home() { # steam_home DIR USER...: a native Steam with these accounts and ~/.steam links
  local h=$1 u
  shift
  mkdir -p "$h/.local/share/Steam/userdata/0/config" "$h/.steam"
  ln -s "$h/.local/share/Steam" "$h/.steam/steam"
  ln -s "$h/.local/share/Steam" "$h/.steam/root"
  for u in "$@"; do mkdir -p "$h/.local/share/Steam/userdata/$u/config"; done
}

echo "# fresh install, piped from curl (INT-28, INT-29, INT-34)"
H1="$T/home one/deck" # a space in HOME, for the quoting
steam_home "$H1" 12345678
run fresh "$H1"
expect_ok fresh
A1=$H1/Applications/Anchorage.AppImage
U1=$H1/.local/share/Steam/userdata/12345678/config
[[ -x $A1 && $(sha "$A1") == $(sha "$T/fake-1.2.0.AppImage") ]] || fail "fresh: AppImage"
[[ $(stat -c %a "$A1") == 755 ]] || fail "fresh: AppImage mode"
D1=$H1/.local/share/applications/$ID.desktop
desktop-file-validate "$D1" || fail "fresh: desktop entry does not validate"
grep -qxF "Exec=\"$A1\"" "$D1" || fail "fresh: Exec line"
cmp -s "$H1/.local/share/icons/hicolor/scalable/apps/$ID.svg" "data/$ID.svg" || fail "fresh: icon"
check ours "$U1/shortcuts.vdf" "$A1" "$U1/grid" "$(art 1.2.0)" 0
check count "$U1/shortcuts.vdf" 1
[[ ! -e $H1/.local/share/Steam/userdata/0/config/shortcuts.vdf ]] || fail "fresh: wrote to userdata/0"
[[ $(find "$H1" -name 'shortcuts.vdf*' | wc -l) == 1 ]] || fail "fresh: wrote more than one shortcuts.vdf (the ~/.steam links)"
grep -q 'Anchorage 1.2.0 is installed' "$LOG" || fail "fresh: summary"
[[ -z $(find "$H1" -name '*.part' -o -name '*.anchorage-new') ]] || fail "fresh: temp files left"
ok "fresh: AppImage, desktop entry, icon, one shortcut with Steam's ID and five grid images"

echo "# rerun and update (INT-33)"
before=$(tree_state "$H1")
run rerun "$H1"
expect_ok rerun
grep -q 'Anchorage 1.2.0 is already installed. Nothing to do.' "$LOG" || fail "rerun: not a no-op"
[[ $(tree_state "$H1") == "$before" ]] || fail "rerun: files changed"
steam_on native
drun rerun-steam "$H1"
expect_ok "rerun with Steam running"
[[ $(tree_state "$H1") == "$before" ]] || fail "rerun with Steam running: files changed"
no_steam_calls "rerun with Steam running"
steam_off
ok "rerun at the same version changes nothing, even while Steam runs"

latest 1.3.0
vdf_before=$(sha "$U1/shortcuts.vdf")
run update "$H1"
expect_ok update
[[ $(sha "$A1") == $(sha "$T/fake-1.3.0.AppImage") ]] || fail "update: AppImage is not 1.3.0"
[[ $(sha "$U1/shortcuts.vdf") == "$vdf_before" ]] || fail "update: shortcuts.vdf changed"
check ours "$U1/shortcuts.vdf" "$A1" "$U1/grid" "$(art 1.3.0)" 0
grep -q 'Anchorage 1.3.0 is installed' "$LOG" || fail "update: summary"
ok "update replaces the AppImage and keeps the shortcut and its ID"

echo "# pinned release copy and --version (INT-34)"
H2=$T/home2
steam_home "$H2" 42
SCRIPT_URL=$URL/download/v1.2.0/install-steamos.sh run pinned "$H2"
expect_ok pinned
[[ $(sha "$H2/Applications/Anchorage.AppImage") == $(sha "$T/fake-1.2.0.AppImage") ]] || fail "pinned: not 1.2.0"
run version "$H2" --version 1.3.0
expect_ok "--version"
[[ $(sha "$H2/Applications/Anchorage.AppImage") == $(sha "$T/fake-1.3.0.AppImage") ]] || fail "--version: not 1.3.0"
run version-missing "$H2" --version 9.9.9
expect_fail "--version 9.9.9" "Is 9.9.9 a released version?"
ok "the release copy installs its own version; --version picks one; a missing one fails"

echo "# existing shortcuts, odd ones, several accounts, Flatpak Steam (INT-28, INT-33)"
H3=$T/home3
steam_home "$H3" 111 222
FP=$H3/.var/app/com.valvesoftware.Steam/.local/share/Steam/userdata/333/config
mkdir -p "$FP"
py "$HERE/fixtures.py" odd "$H3/.local/share/Steam/userdata/111/config/shortcuts.vdf"
py "$HERE/fixtures.py" nonseq "$H3/.local/share/Steam/userdata/222/config/shortcuts.vdf"
py "$HERE/fixtures.py" simple "$FP/shortcuts.vdf"
mkdir -p "$T/orig3"
cp "$H3/.local/share/Steam/userdata/111/config/shortcuts.vdf" "$T/orig3/111.vdf"
cp "$H3/.local/share/Steam/userdata/222/config/shortcuts.vdf" "$T/orig3/222.vdf"
cp "$FP/shortcuts.vdf" "$T/orig3/333.vdf"
mkdir -p "$H3/.local/share/Steam/userdata/111/config/grid"
echo keep >"$H3/.local/share/Steam/userdata/111/config/grid/2147483649p.png"
A3=$H3/Applications/Anchorage.AppImage
dry_before=$(tree_state "$H3")
run dry "$H3" --dry-run
expect_ok "--dry-run"
grep -q 'would add the shortcut' "$LOG" || fail "--dry-run: no plan"
[[ $(tree_state "$H3") == "$dry_before" ]] || fail "--dry-run changed files"
ok "--dry-run says what it would do and changes nothing"

steam_on native
run running "$H3"
expect_fail "Steam running, no display" "Steam is running"
grep -q 'steam -shutdown' "$LOG" || fail "Steam running: no way to close it"
grep -q 'Without a desktop (no DISPLAY or WAYLAND_DISPLAY)' "$LOG" || fail "Steam running, no display: no reason"
[[ $(tree_state "$H3") == "$dry_before" ]] || fail "Steam running: files changed"
no_steam_calls "Steam running, no display"
steam_off
ok "with Steam running, a shortcut to add and no display, it changes nothing and says how to close Steam"

run existing "$H3"
expect_ok existing
for u in 111 222; do
  key=$([[ $u == 111 ]] && echo 5 || echo 6)
  v=$H3/.local/share/Steam/userdata/$u/config
  check appended "$T/orig3/$u.vdf" "$v/shortcuts.vdf" "$key"
  check ours "$v/shortcuts.vdf" "$A3" "$v/grid" "$(art 1.3.0)" "$key"
  backups=("$v"/shortcuts.vdf.anchorage-backup-*)
  if [[ ${#backups[@]} != 1 ]] || ! cmp -s "${backups[0]}" "$T/orig3/$u.vdf"; then fail "existing $u: backup"; fi
done
check appended "$T/orig3/333.vdf" "$FP/shortcuts.vdf" 2
check ours "$FP/shortcuts.vdf" "$A3" "$FP/grid" "$(art 1.3.0)" 2
[[ $(cat "$H3/.local/share/Steam/userdata/111/config/grid/2147483649p.png") == keep ]] || fail "existing: other art changed"
grep -q 'flatpak override --user --filesystem=~/Applications' "$LOG" || fail "existing: no Flatpak note"
ok "adds to every account (native and Flatpak), keeps every other byte, backs up first"

echo "# an older Anchorage AppImage in ~/Applications (INT-29, INT-33)"
H4=$T/home4
steam_home "$H4" 7
V4=$H4/.local/share/Steam/userdata/7/config
py "$HERE/fixtures.py" legacy "$V4/shortcuts.vdf" "$H4/Applications" 3000000001
cp "$V4/shortcuts.vdf" "$T/legacy.vdf"
run legacy "$H4"
expect_ok legacy
check legacy "$T/legacy.vdf" "$V4/shortcuts.vdf" 1 "$H4/Applications/Anchorage.AppImage"
for f in p "" _hero _logo _icon; do [[ -f $V4/grid/3000000001$f.png ]] || fail "legacy: art $f"; done
ok "an older Anchorage shortcut gets the new path and keeps its ID and other fields"

echo "# uninstall (INT-33)"
steam_on native
before=$(tree_state "$H3")
run uninstall-running "$H3" --uninstall
expect_fail "uninstall with Steam running" "Steam is running"
[[ $(tree_state "$H3") == "$before" ]] || fail "uninstall with Steam running: files changed"
no_steam_calls "uninstall with Steam running, no display"
steam_off
run uninstall "$H3" --uninstall
expect_ok uninstall
for u in 111 222; do
  cmp -s "$H3/.local/share/Steam/userdata/$u/config/shortcuts.vdf" "$T/orig3/$u.vdf" || fail "uninstall $u: not the original bytes"
done
cmp -s "$FP/shortcuts.vdf" "$T/orig3/333.vdf" || fail "uninstall 333: not the original bytes"
[[ -z $(find "$H3" -path '*/grid/*' ! -name 2147483649p.png -type f) ]] || fail "uninstall: art left"
[[ ! -e $A3 && ! -e $H3/.local/share/applications/$ID.desktop && ! -e $H3/.local/share/icons/hicolor/scalable/apps/$ID.svg ]] ||
  fail "uninstall: files left"
[[ -f $H3/.local/share/Steam/userdata/111/config/grid/2147483649p.png ]] || fail "uninstall: removed other art"
run uninstall-again "$H3" --uninstall
expect_ok "uninstall again"
grep -q 'Nothing to do' "$LOG" || fail "uninstall again: not a no-op"
ok "uninstall restores the original files byte for byte, removes only its own files; again is a no-op"

H5=$T/home5
steam_home "$H5" 9
V5=$H5/.local/share/Steam/userdata/9/config
mkdir -p "$H5/Applications" "$H5/.local/share/applications"
py "$HERE/fixtures.py" middle "$V5/shortcuts.vdf" "$T/middle-expected.vdf" "$H5/Applications/Anchorage.AppImage"
echo "[Desktop Entry]" >"$H5/.local/share/applications/$ID.desktop"
run uninstall-middle "$H5" --uninstall
expect_ok "uninstall middle"
cmp -s "$V5/shortcuts.vdf" "$T/middle-expected.vdf" || fail "uninstall middle: not the expected bytes"
check count "$V5/shortcuts.vdf" 2
[[ -f $H5/.local/share/applications/$ID.desktop ]] || fail "uninstall: removed a desktop entry it did not write"
ok "uninstall of a shortcut in the middle renumbers the next one and keeps its bytes; keeps a foreign desktop entry"

echo "# an account folder without config/ (INT-28, INT-33)"
H8=$T/home8
steam_home "$H8" 5
mkdir -p "$H8/.local/share/Steam/userdata/77/760/remote"
run noconfig "$H8"
expect_ok "account without config"
grep -q 'account 77: skipped' "$LOG" || fail "account without config: no note"
[[ ! -e $H8/.local/share/Steam/userdata/77/config ]] || fail "account without config: config created"
check ours "$H8/.local/share/Steam/userdata/5/config/shortcuts.vdf" "$H8/Applications/Anchorage.AppImage" \
  "$H8/.local/share/Steam/userdata/5/config/grid" "$(art 1.3.0)" 0
ok "an account folder without config/ is skipped with a note; the others get the shortcut"

echo "# the user's own artwork and files, backups (INT-33)"
H10=$T/home10
steam_home "$H10" 10
G10=$H10/.local/share/Steam/userdata/10/config/grid
run art-1.2 "$H10" --version 1.2.0
expect_ok "art 1.2.0"
STATE10=$H10/.local/state/anchorage-installer/files.sha256
[[ -f $STATE10 ]] || fail "no list of written files"
id10=$(py "$HERE/check.py" appid "\"$H10/Applications/Anchorage.AppImage\"" Anchorage)
echo mine >"$G10/${id10}p.png"
run art-1.3 "$H10" --version 1.3.0
expect_ok "art 1.3.0"
[[ $(cat "$G10/${id10}p.png") == mine ]] || fail "update replaced the user's portrait"
grep -q "kept .*${id10}p.png" "$LOG" || fail "update: no note about the kept portrait"
cmp -s "$G10/${id10}_hero.png" "$(art 1.3.0)/steam-hero.png" || fail "update: hero is not 1.3.0's"
before=$(tree_state "$H10")
run art-again "$H10" --version 1.3.0
expect_ok "art again"
[[ $(tree_state "$H10") == "$before" ]] || fail "rerun with the user's art: files changed"
for t in 20200101-000001 20200101-000002 20200101-000003 20200101-000004; do
  echo old >"$H10/.local/share/Steam/userdata/10/config/shortcuts.vdf.anchorage-backup-$t"
done
run art-uninstall "$H10" --uninstall
expect_ok "art uninstall"
[[ $(cat "$G10/${id10}p.png") == mine ]] || fail "uninstall removed the user's portrait"
[[ ! -e $G10/${id10}_hero.png && ! -e $H10/Applications/Anchorage.AppImage && ! -e $STATE10 ]] ||
  fail "uninstall left its own files"
mapfile -t backups < <(find "$H10/.local/share/Steam/userdata/10/config" -name 'shortcuts.vdf.anchorage-backup-*' | sort)
[[ ${#backups[@]} == 3 && ${backups[0]} == *20200101-000003 && ${backups[1]} == *20200101-000004 ]] ||
  fail "backups: ${backups[*]}"
ok "artwork the user set is kept on update and uninstall; at most three backups are kept"

H11=$T/home11
steam_home "$H11" 11
run own-files "$H11"
expect_ok "own files"
echo "my own build" >"$H11/Applications/Anchorage.AppImage"
echo "<svg/>" >"$H11/.local/share/icons/hicolor/scalable/apps/$ID.svg"
run own-uninstall "$H11" --uninstall
expect_ok "own files uninstall"
[[ $(cat "$H11/Applications/Anchorage.AppImage") == "my own build" ]] || fail "uninstall removed an AppImage it did not write"
[[ -f $H11/.local/share/icons/hicolor/scalable/apps/$ID.svg ]] || fail "uninstall removed an icon it did not write"
grep -q 'kept ~/Applications/Anchorage.AppImage' "$LOG" || fail "own files: no note"
check count "$H11/.local/share/Steam/userdata/11/config/shortcuts.vdf" 0
ok "uninstall keeps an AppImage and icon that are not the ones it wrote, and still removes the shortcut"

echo "# a large shortcuts.vdf (INT-33)"
H9=$T/home9
steam_home "$H9" 9
V9=$H9/.local/share/Steam/userdata/9/config
py "$HERE/fixtures.py" many "$V9/shortcuts.vdf" 1000
cp "$V9/shortcuts.vdf" "$T/many.vdf"
start=$(date +%s)
run many "$H9"
expect_ok "1000 shortcuts"
echo "    1000 shortcuts: $(($(date +%s) - start)) s"
grep -q 'reading the shortcuts of account 9' "$LOG" || fail "1000 shortcuts: no progress line"
check appended "$T/many.vdf" "$V9/shortcuts.vdf" 1000
# Ctrl-C while it checks the new file (uninstall): no temp file is left. Job control gives
# the run its own process group, which a background job would otherwise not get.
mkdir -p "$T/int"
LOG=$T/interrupt.log
set +e -m
# shellcheck disable=SC2016 # expanded by the inner bash
env -i HOME="$H9" PATH="$BASE_PATH" LANG=C.UTF-8 TMPDIR="$T/int" \
  ANCHORAGE_API_URL="$URL/api" ANCHORAGE_DOWNLOAD_BASE="$URL/download" \
  bash -c 'bash -s -- --uninstall <"$1"' _ "$REPO/scripts/install-steamos.sh" >"$LOG" 2>&1 &
pid=$!
for _ in $(seq 600); do
  [[ -e $V9/shortcuts.vdf.anchorage-new ]] && break
  sleep 0.05
done
[[ -e $V9/shortcuts.vdf.anchorage-new ]] || fail "interrupt: the new file never appeared"
kill -INT -- "-$pid"
wait "$pid"
set -e +m
[[ ! -e $V9/shortcuts.vdf.anchorage-new ]] || fail "interrupt: left shortcuts.vdf.anchorage-new"
[[ -z $(ls -A "$T/int") ]] || fail "interrupt: left its temp dir"
cmp -s "$T/many.vdf" "$V9/shortcuts.vdf" && fail "interrupt: the uninstall had already finished"
ok "1000 shortcuts: a progress line, appended byte for byte; Ctrl-C leaves no temp file"

echo "# closing and restarting Steam (INT-33, INT-35)"
simple_home() { # simple_home DIR ID: native Steam, one account with two shortcuts; VDF is its file
  steam_home "$1" "$2"
  VDF=$1/.local/share/Steam/userdata/$2/config/shortcuts.vdf
  py "$HERE/fixtures.py" simple "$VDF"
}
h16() { sha256sum "$1" | cut -c1-16; }
H12=$T/home12
simple_home "$H12" 12
V12=$VDF
cp "$V12" "$T/simple12.vdf"
orig=$(h16 "$V12")
steam_on native exits "$V12"
XENV=(ANCHORAGE_COUNTDOWN=5)
drun restart "$H12"
XENV=()
expect_ok "restart"
log_wait "native start" || fail "restart: Steam was not started again"
new=$(h16 "$V12")
check appended "$T/simple12.vdf" "$V12" 2
mapfile -t calls <"$S/log"
[[ ${#calls[@]} == 3 && ${calls[0]} == "native shutdown $orig" && ${calls[1]} == "native exited $orig" &&
  ${calls[2]} == "native start -silent $new display=:0/wayland-0 detached=yes" ]] ||
  fail "restart: the calls were: ${calls[*]}"
[[ -e $S/native ]] || fail "restart: Steam is not running at the end"
grep -q 'closing Steam in 5 4 3 2 1$' "$LOG" || fail "restart: no countdown"
grep -q 'Press Ctrl+C in the next 5 seconds to cancel' "$LOG" || fail "restart: no way to cancel"
grep -q 'waiting for Steam to exit.* closed' "$LOG" || fail "restart: no progress"
grep -q 'Steam is starting again' "$LOG" || fail "restart: summary"
ok "Steam running: countdown, steam -shutdown, the edit only after it exited, steam -silent once, detached, same display"

before=$(tree_state "$H12")
steam_on native exits "$V12"
drun restart-none "$H12"
expect_ok "nothing to change, Steam running"
grep -q 'Nothing to do' "$LOG" || fail "nothing to change: not a no-op"
[[ $(tree_state "$H12") == "$before" ]] || fail "nothing to change: files changed"
no_steam_calls "nothing to change"
id12=$(py "$HERE/check.py" appid "\"$H12/Applications/Anchorage.AppImage\"" Anchorage)
G12=$H12/.local/share/Steam/userdata/12/config/grid
rm "$G12/${id12}_hero.png"
steam_on native exits "$V12"
drun restart-art "$H12"
expect_ok "artwork to write, Steam running"
log_wait "native start" || fail "artwork: Steam was not started again"
[[ $(grep -c . "$S/log") == 3 && $(starts) == 1 ]] || fail "artwork: the calls were: $(cat "$S/log")"
cmp -s "$G12/${id12}_hero.png" "$(art 1.3.0)/steam-hero.png" || fail "artwork: hero not written"
H13=$T/home13
simple_home "$H13" 13
steam_off
drun restart-off "$H13"
expect_ok "Steam not running"
check appended "$T/simple12.vdf" "$VDF" 2
no_steam_calls "Steam not running"
ok "no Steam calls when nothing changes or Steam is not running; missing artwork alone closes and restarts it"

H14=$T/home14
simple_home "$H14" 14
before=$(tree_state "$H14")
steam_on native stuck "$VDF"
XENV=(ANCHORAGE_STEAM_WAIT=2)
drun stuck "$H14"
XENV=()
expect_fail "Steam never exits" "Steam did not close within 2 seconds, so nothing was changed"
[[ $(tree_state "$H14") == "$before" ]] || fail "Steam never exits: files changed"
[[ -e $S/native ]] || fail "Steam never exits: Steam was stopped"
sleep 0.3
[[ $(cat "$S/log") == "native shutdown $(h16 "$VDF")" ]] || fail "Steam never exits: the calls were: $(cat "$S/log")"
ok "a Steam that never exits: nothing changed (not even ~/Applications), not killed, not started twice, exit non-zero"

H15=$T/home15
simple_home "$H15" 15
cp "$VDF" "$T/simple15.vdf"
chmod 555 "${VDF%/*}"
steam_on native exits "$VDF"
drun trap "$H15"
chmod 755 "${VDF%/*}"
[[ $STATUS != 0 ]] || fail "failure mid-edit: exit 0"
log_wait "native start" || fail "failure mid-edit: Steam was not started again"
[[ $(starts) == 1 ]] || fail "failure mid-edit: the calls were: $(cat "$S/log")"
cmp -s "$VDF" "$T/simple15.vdf" || fail "failure mid-edit: shortcuts.vdf changed"
ok "a failure after Steam was closed (unwritable config folder) still starts Steam again, once"

H16=$T/home16
simple_home "$H16" 16
before=$(tree_state "$H16")
steam_on native exits "$VDF"
LOG=$T/cancel.log
set +e -m
# shellcheck disable=SC2016 # expanded by the inner bash
env -i HOME="$H16" PATH="$BASE_PATH" LANG=C.UTF-8 TMPDIR="$T/tmp" "${DESKTOP_ENV[@]}" ANCHORAGE_COUNTDOWN=5 \
  ANCHORAGE_API_URL="$URL/api" ANCHORAGE_DOWNLOAD_BASE="$URL/download" \
  bash -c 'bash -s <"$1"' _ "$REPO/scripts/install-steamos.sh" >"$LOG" 2>&1 &
pid=$!
for _ in $(seq 100); do
  grep -q 'closing Steam in 5' "$LOG" && break
  sleep 0.05
done
grep -q 'closing Steam in 5' "$LOG" || fail "cancel: the countdown never started"
kill -INT -- "-$pid"
wait "$pid"
set -e +m
[[ $(tree_state "$H16") == "$before" ]] || fail "cancel: files changed"
[[ -e $S/native ]] || fail "cancel: Steam was stopped"
no_steam_calls "Ctrl+C in the countdown"
ok "Ctrl+C in the countdown: Steam not touched, nothing changed"

H18=$T/home18
simple_home "$H18" 18
cp "$VDF" "$T/simple18.vdf"
steam_on native exits "$VDF"
LOG=$T/cancel-late.log
set +e -m
# shellcheck disable=SC2016 # expanded by the inner bash
env -i HOME="$H18" PATH="$BASE_PATH" LANG=C.UTF-8 TMPDIR="$T/tmp" "${DESKTOP_ENV[@]}" \
  ANCHORAGE_API_URL="$URL/api" ANCHORAGE_DOWNLOAD_BASE="$URL/download" \
  bash -c 'bash -s <"$1"' _ "$REPO/scripts/install-steamos.sh" >"$LOG" 2>&1 &
pid=$!
for _ in $(seq 100); do
  grep -q 'waiting for Steam to exit' "$LOG" && break
  sleep 0.05
done
grep -q 'waiting for Steam to exit' "$LOG" || fail "late Ctrl+C: Steam was never closed"
kill -INT -- "-$pid"
wait "$pid"
STATUS=$?
set -e +m
expect_ok "Ctrl+C while Steam closes"
log_wait "native start" || fail "late Ctrl+C: Steam was not started again"
[[ $(starts) == 1 ]] || fail "late Ctrl+C: the calls were: $(cat "$S/log")"
check appended "$T/simple18.vdf" "$VDF" 2
ok "Ctrl+C after the countdown is ignored: the install finishes and Steam starts again, once"

steam_on native exits "$VDF"
drun no-restart "$H16" --no-steam-restart
expect_fail "--no-steam-restart" "Steam is running"
grep -q 'steam -shutdown' "$LOG" || fail "--no-steam-restart: no way to close it"
[[ $(tree_state "$H16") == "$before" ]] || fail "--no-steam-restart: files changed"
no_steam_calls "--no-steam-restart"
XENV=(SSH_CONNECTION="10.0.0.2 50000 10.0.0.3 22")
drun ssh "$H16"
expect_fail "over SSH" "Over SSH it can't start Steam again"
no_steam_calls "over SSH"
XENV=(SteamGameId=12345)
drun under-steam "$H16"
expect_fail "terminal started by Steam" "This terminal was started by Steam"
no_steam_calls "terminal started by Steam"
XENV=()
[[ $(tree_state "$H16") == "$before" ]] || fail "fallbacks: files changed"
drun dry-steam "$H16" --dry-run
expect_ok "--dry-run, Steam running"
if ! grep -q 'would close it (steam -shutdown), make the changes and start it' "$LOG" ||
  ! grep -q 'again (steam -silent)' "$LOG"; then
  fail "--dry-run: does not say it would close and restart Steam"
fi
[[ $(tree_state "$H16") == "$before" ]] || fail "--dry-run, Steam running: files changed"
no_steam_calls "--dry-run"
ok "--no-steam-restart, SSH and a terminal Steam started stop with instructions; --dry-run says it would restart Steam"

steam_on native exits "$V12"
installed=$(h16 "$V12")
drun restart-uninstall "$H12" --uninstall
expect_ok "uninstall, Steam running"
log_wait "native start" || fail "uninstall: Steam was not started again"
cmp -s "$V12" "$T/simple12.vdf" || fail "uninstall, Steam running: not the original bytes"
mapfile -t calls <"$S/log"
[[ ${#calls[@]} == 3 && ${calls[0]} == "native shutdown $installed" && ${calls[1]} == "native exited $installed" &&
  ${calls[2]} == "native start -silent $orig display=:0/wayland-0 detached=yes" ]] ||
  fail "uninstall: the calls were: ${calls[*]}"
ok "uninstall closes Steam, removes the shortcut, starts Steam again once"

H17=$T/home17
FP17=$H17/.var/app/com.valvesoftware.Steam/.local/share/Steam/userdata/17/config
mkdir -p "$FP17"
py "$HERE/fixtures.py" simple "$FP17/shortcuts.vdf"
orig=$(h16 "$FP17/shortcuts.vdf")
steam_on flatpak exits "$FP17/shortcuts.vdf"
drun flatpak "$H17"
expect_ok "Flatpak Steam"
log_wait "flatpak start" || fail "Flatpak: Steam was not started again"
new=$(h16 "$FP17/shortcuts.vdf")
mapfile -t calls <"$S/log"
[[ ${#calls[@]} == 3 && ${calls[0]} == "flatpak shutdown $orig" && ${calls[1]} == "flatpak exited $orig" &&
  ${calls[2]} == "flatpak start -silent $new display=:0/wayland-0 detached=yes" ]] ||
  fail "Flatpak: the calls were: ${calls[*]}"
grep -q 'flatpak run com.valvesoftware.Steam -shutdown' "$LOG" || fail "Flatpak: output"
ok "Flatpak Steam: flatpak run com.valvesoftware.Steam -shutdown, then -silent, once"

steam_off
(
  # shellcheck source=/dev/null
  source <(sed '/^main "\$@"$/d' scripts/install-steamos.sh)
  unset DISPLAY WAYLAND_DISPLAY
  mkdir -p "$T/nosetsid"
  for t in nohup sh cat cut sha256sum touch rm sleep; do ln -s "$(command -v "$t")" "$T/nosetsid/$t"; done
  ln -s "$T/bin/steam" "$T/nosetsid/steam"
  PATH=$T/nosetsid detach steam -silent
)
log_wait "native start -silent none display=/ detached=no" || fail "nohup: $(cat "$S/log" 2>/dev/null)"
steam_off
ok "without setsid, Steam is started with nohup"

echo "# failures"
H6=$T/home6
steam_home "$H6" 1 2
py "$HERE/fixtures.py" garbage "$H6/.local/share/Steam/userdata/1/config/shortcuts.vdf"
cp "$H6/.local/share/Steam/userdata/1/config/shortcuts.vdf" "$T/garbage.vdf"
run garbage "$H6"
expect_fail "unreadable shortcuts.vdf" "Could not read"
cmp -s "$H6/.local/share/Steam/userdata/1/config/shortcuts.vdf" "$T/garbage.vdf" || fail "garbage: file changed"
check ours "$H6/.local/share/Steam/userdata/2/config/shortcuts.vdf" "$H6/Applications/Anchorage.AppImage" \
  "$H6/.local/share/Steam/userdata/2/config/grid" "$(art 1.3.0)"
ok "an unreadable shortcuts.vdf is left alone, the other account still gets the shortcut, and it exits non-zero"

H7=$T/home7
steam_home "$H7" 1
run checksum "$H7" --version 6.6.6
expect_fail "checksum mismatch" "does not match the checksum"
[[ ! -e $H7/Applications/Anchorage.AppImage && -z $(find "$H7" -name '*.part') ]] || fail "checksum: installed or left a part file"
[[ ! -e $H7/.local/share/Steam/userdata/1/config/shortcuts.vdf ]] || fail "checksum: shortcut added"

mkdir -p "$T/nocurl"
for t in od dd sha256sum mktemp readlink cmp grep stat sort sed id uname cp mv rm mkdir chmod date cat head; do
  ln -s "$(command -v "$t")" "$T/nocurl/$t"
done
LOG=$T/nocurl.log
set +e
env -i HOME="$H7" PATH="$T/nocurl" TMPDIR="$T/tmp" "$(command -v bash)" -s <scripts/install-steamos.sh >"$LOG" 2>&1
STATUS=$?
set -e
expect_fail "no curl" "This needs curl"
printf '{"tag_name": "v4.0.4"}' >"$SRV/api/releases/latest"
run no-release "$H7"
expect_fail "missing release assets" "Could not download"
[[ ! -e $H7/Applications/Anchorage.AppImage ]] || fail "missing assets: installed something"
ok "a bad checksum, a missing curl and a release without assets fail and install nothing"

echo "# after Anchorage updated itself (UPD-7)"
H20=$T/home20
steam_home "$H20" 20
latest 1.2.0
run self-fresh "$H20"
expect_ok "install before a self-update"
A20=$H20/Applications/Anchorage.AppImage
M20=$H20/.local/state/anchorage-installer/files.sha256
NEW=$(sha "$T/fake-1.3.0.AppImage")
LOG=$T/self-swap.log
mkdir -p "$T/godot"
HOME=$T/godot XDG_DATA_HOME=$T/godot XDG_CONFIG_HOME=$T/godot XDG_CACHE_HOME=$T/godot \
  godot --headless --path app -s res://tests/self_update_swap.gd -- "$M20" "$A20" \
  "$T/fake-1.3.0.AppImage" >"$LOG" 2>&1 || fail "the app's swap failed"
[[ $(sha "$A20") == "$NEW" && $(sha "$A20.previous") == $(sha "$T/fake-1.2.0.AppImage") ]] ||
  fail "self-update: not swapped"
grep -qxF "$NEW  $A20" "$M20" || fail "self-update: the record does not list the new hash"
rm -f "$A20.previous" # what the new version does once it has run 10 s
latest 1.3.0
before=$(tree_state "$H20")
run self-rerun "$H20"
expect_ok "rerun after a self-update"
grep -q 'Anchorage 1.3.0 is already installed. Nothing to do.' "$LOG" || fail "rerun after a self-update: not a no-op"
[[ $(tree_state "$H20") == "$before" ]] || fail "rerun after a self-update: files changed"
run self-uninstall "$H20" --uninstall
expect_ok "uninstall after a self-update"
[[ ! -e $A20 ]] || fail "uninstall after a self-update kept the AppImage"
ok "after a self-update a rerun changes nothing and --uninstall still removes the AppImage"

echo "$PASS checks passed"
