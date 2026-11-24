#!/usr/bin/env bash
# Stages the files a GitHub release attaches (INT-25, INT-28, INT-34): the AppImage, the
# Steam art from data/steam/, the app icon, install-steamos.sh pinned to this version,
# and SHA256SUMS over all of them. Prints the staged files, one per line.
# Usage: scripts/release-assets.sh X.Y.Z [APPIMAGE] [OUTDIR]
#   APPIMAGE defaults to dist/Anchorage-X.Y.Z-x86_64.AppImage, OUTDIR to dist/vX.Y.Z.
set -euo pipefail
cd "$(dirname "$0")/.."

ID=io.github.DisposableSoftware.Anchorage
v=${1:-}
v=${v#v}
[[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 X.Y.Z [APPIMAGE] [OUTDIR]" >&2; exit 2; }
img=${2:-dist/Anchorage-$v-x86_64.AppImage}
out=${3:-dist/v$v}
[[ -f $img ]] || { echo "no AppImage at $img: run scripts/build-appimage.sh first" >&2; exit 1; }

rm -rf -- "$out"
mkdir -p -- "$out"
files=("Anchorage-$v-x86_64.AppImage")
install -m755 -- "$img" "$out/${files[0]}"
for n in portrait wide hero logo icon; do
  install -m644 -- "data/steam/$n.png" "$out/steam-$n.png"
  files+=("steam-$n.png")
done
install -m644 -- "data/$ID.svg" "$out/$ID.svg"
files+=("$ID.svg")
sed "s/^PINNED_VERSION=\"\"\$/PINNED_VERSION=\"$v\"/" scripts/install-steamos.sh >"$out/install-steamos.sh"
grep -qx "PINNED_VERSION=\"$v\"" "$out/install-steamos.sh" ||
  { echo "install-steamos.sh has no PINNED_VERSION=\"\" line to set" >&2; exit 1; }
chmod 755 -- "$out/install-steamos.sh"
files+=(install-steamos.sh)
(cd "$out" && sha256sum -- "${files[@]}" >SHA256SUMS)
files+=(SHA256SUMS)
for f in "${files[@]}"; do echo "$out/$f"; done
