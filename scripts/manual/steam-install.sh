#! /usr/bin/env nix-shell
#! nix-shell -i bash -p "python3.withPackages (ps: [ ps.vdf ])" shellcheck curl desktop-file-utils
# shellcheck shell=bash
# Spec: INT-28, INT-29, INT-33, INT-34.
# Runs scripts/install-steamos.sh the way `curl ... | bash` does, against fake HOME and
# Steam folders, a fake GitHub API and fake release assets served from 127.0.0.1, and a
# fake pgrep that says whether Steam runs. The results are read back with an independent
# VDF parser (ValvePython's vdf, scripts/manual/steam-install/check.py) and compared
# byte for byte with the files before. Nothing outside a temp dir is touched, and no real
# Steam, release or network is used. Also runs shellcheck on the scripts.
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

# Fake pgrep: Steam runs when $T/steam-running exists.
mkdir -p "$T/bin" "$T/tmp"
cat >"$T/bin/pgrep" <<EOF
#!/bin/sh
[ "\$*" = "-x steam" ] && [ -e "$T/steam-running" ]
EOF
chmod +x "$T/bin/pgrep"
BASE_PATH=$T/bin:$PATH

# run NAME HOME [ARGS...]: pipes the script from the fake raw URL into bash, as the
# README's command does. SCRIPT_URL picks another copy.
run() {
  local name=$1 home=$2
  shift 2
  LOG=$T/$name.log
  set +e
  # shellcheck disable=SC2016 # expanded by the inner bash
  env -i HOME="$home" PATH="$BASE_PATH" LANG=C.UTF-8 TMPDIR="$T/tmp" \
    ANCHORAGE_API_URL="$URL/api" ANCHORAGE_DOWNLOAD_BASE="$URL/download" \
    bash -c 'curl -fsSL "$1" | bash -s -- "${@:2}"' _ "${SCRIPT_URL:-$URL/raw/install-steamos.sh}" "$@" >"$LOG" 2>&1
  STATUS=$?
  set -e
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
touch "$T/steam-running"
run rerun-steam "$H1"
rm "$T/steam-running"
expect_ok "rerun with Steam running"
[[ $(tree_state "$H1") == "$before" ]] || fail "rerun with Steam running: files changed"
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

touch "$T/steam-running"
run running "$H3"
rm "$T/steam-running"
expect_fail "Steam running" "Steam is running"
grep -q 'steam -shutdown' "$LOG" || fail "Steam running: no way to close it"
[[ $(tree_state "$H3") == "$dry_before" ]] || fail "Steam running: files changed"
ok "with Steam running and a shortcut to add, it changes nothing and says how to close Steam"

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
touch "$T/steam-running"
before=$(tree_state "$H3")
run uninstall-running "$H3" --uninstall
rm "$T/steam-running"
expect_fail "uninstall with Steam running" "Steam is running"
[[ $(tree_state "$H3") == "$before" ]] || fail "uninstall with Steam running: files changed"
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
for t in od dd sha256sum mktemp readlink cmp grep sed id uname cp mv rm mkdir chmod date cat head; do
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

echo "$PASS checks passed"
