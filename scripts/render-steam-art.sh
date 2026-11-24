#!/usr/bin/env bash
# Draws the app icons and the Steam library artwork (INT-27, INT-42): runs
# tools/steam-art/generate.py for the SVGs, then renders data/steam/*.png from them.
# The tools come from tools/steam-art/shell.nix (the flake's pinned nixpkgs), so the
# output is the same on every machine.
# Usage: scripts/render-steam-art.sh           write the files
#        scripts/render-steam-art.sh --check   fail if the committed files are out of date
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${IN_STEAM_ART_SHELL:-}" ]; then
  IN_STEAM_ART_SHELL=1 exec nix-shell tools/steam-art/shell.nix --run "$(printf '%q ' "$0" "$@")"
fi

ID=io.github.DisposableSoftware.Anchorage
FILES=(data/steam/{portrait,wide,hero,logo}.{svg,png} data/steam/icon.png
       "data/$ID.svg" "data/$ID-symbolic.svg" app/icon.svg)

render() { # render <root>
  python3 tools/steam-art/generate.py "$1" >/dev/null
  for n in portrait wide hero logo; do
    rsvg-convert "$1/data/steam/$n.svg" -o "$1/data/steam/$n.png"
  done
  rsvg-convert -w 256 -h 256 "$1/data/$ID.svg" -o "$1/data/steam/icon.png"
}

if [ "${1:-}" = --check ]; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/app/fonts"
  cp app/fonts/InterVariable.ttf "$tmp/app/fonts/"
  render "$tmp"
  stale=0
  for f in "${FILES[@]}"; do
    cmp -s "$f" "$tmp/$f" || { echo "out of date: $f" >&2; stale=1; }
  done
  [ $stale = 0 ] && echo "steam art is up to date"
  exit $stale
fi

render .
printf '%s\n' "${FILES[@]}"
