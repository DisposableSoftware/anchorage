#!/usr/bin/env bash
# Refuses to let ROMs, game assets or large binaries into a push.
# Usage: scripts/check-no-roms.sh [REV-LIST-ARGS...]
# The default checks every object reachable from HEAD that no remote-tracking ref has.
# Fails on: a ROM-like or game-asset file name, an N64 ROM header (z64, v64 or n64 byte
# order) at the start of any file, and any file over 5 MiB. The pre-push hook runs it
# for every push; Anchorage never needs to ship any of these.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

if [ $# -eq 0 ]; then set -- HEAD --not --remotes; fi
max=$((5 * 1024 * 1024))
bad=0

deny='\.(z64|n64|v64|u64|rom|bin|zip|7z|rar|gz|xz|zst|tar|iso|rvz|wbfs|gcm|nes|smc|sfc|gb|gbc|gba|nds|3ds|o2r|otr|appimage)$'

while read -r type sha size path; do
  [ "$type" = blob ] || continue
  [ -n "$path" ] || continue
  lower=$(tr '[:upper:]' '[:lower:]' <<<"$path")
  if grep -qiE "$deny" <<<"$lower"; then
    echo "check-no-roms: $path looks like a ROM, archive or game asset" >&2; bad=1; continue
  fi
  if [ "$size" -gt "$max" ]; then
    echo "check-no-roms: $path is $((size / 1024 / 1024)) MiB (limit 5 MiB)" >&2; bad=1; continue
  fi
  magic=$(git cat-file blob "$sha" | head -c 4 | od -An -tx1 | tr -d ' \n')
  case $magic in
    80371240 | 37804012 | 40123780)
      echo "check-no-roms: $path starts with an N64 ROM header" >&2; bad=1 ;;
  esac
done < <(git rev-list --objects "$@" | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)')

if [ "$bad" = 1 ]; then
  echo "check-no-roms: refusing. Nothing was pushed." >&2
  exit 1
fi
