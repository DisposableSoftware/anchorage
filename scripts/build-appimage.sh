#!/usr/bin/env bash
# Builds dist/Anchorage-<version>-x86_64.AppImage with `nix build .#appimage` (INT-26).
# The Godot export templates and the AppImage runtime are the only downloads, both pinned.
# Usage: scripts/build-appimage.sh   (prints the path of the AppImage)
set -euo pipefail
cd "$(dirname "$0")/.."

out=$(nix build .#appimage --no-link --print-out-paths)
mkdir -p dist
for f in "$out"/Anchorage-*-x86_64.AppImage; do
  install -m755 "$f" dist/
  echo "dist/$(basename "$f")"
done
