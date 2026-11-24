#!/usr/bin/env bash
# Refuses to let ROMs, game assets or large binaries into a push.
# Usage: scripts/check-no-roms.sh [REV-LIST-ARGS...]
# The default checks every object reachable from HEAD that no remote-tracking ref has.
# Fails on: a ROM-like or game-asset file name; an N64 ROM header, or an archive or
# compressed-stream header (zip, gzip, xz, bzip2, zstd, lz4, 7z, rar), at the start of any
# file whatever its name; a file name with a control character; any file over 5 MiB; and
# any error while listing the objects (it fails closed). Anchorage ships none of these.
# The pre-push hook runs it for every push.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

if [ $# -eq 0 ]; then set -- HEAD --not --remotes; fi
max=$((5 * 1024 * 1024))
bad=0

deny='\.(z64|n64|v64|u64|ndd|rom|bin|d64|zip|7z|rar|gz|tgz|bz2|xz|lz4|lzma|zst|tar|iso|rvz|wbfs|gcm|nes|smc|sfc|gb|gbc|gba|nds|3ds|o2r|otr|appimage)$'

list=$(mktemp) || exit 1
trap 'rm -f "$list"' EXIT
if ! git rev-list --objects "$@" >"$list" 2>"$list.err"; then
  echo "check-no-roms: cannot list the objects to check:" >&2
  cat "$list.err" >&2
  echo "check-no-roms: refusing (fail closed). Nothing was pushed." >&2
  rm -f "$list.err"
  exit 1
fi
rm -f "$list.err"

# A line that is not "<40 hex>" or "<40 hex> <path>" is the tail of a path with a newline.
if grep -qvE '^[0-9a-f]{40}( .*)?$' "$list"; then
  echo "check-no-roms: a file name contains a control character; refusing" >&2
  exit 1
fi

# `rev-list --objects` cuts a path at a newline, so the names are also read NUL-separated from
# every commit's tree, where nothing is lost.
while read -r commit; do
  while IFS= read -r -d '' p; do
    if [[ $p == *[[:cntrl:]]* ]]; then
      echo "check-no-roms: a file name contains a control character; refusing" >&2; bad=1; continue
    fi
    lp=$(tr '[:upper:]' '[:lower:]' <<<"$p")
    if grep -qE "$deny" <<<"$lp"; then
      echo "check-no-roms: $p looks like a ROM, archive or game asset" >&2; bad=1
    fi
  done < <(git ls-tree -r -z --name-only "$commit")
done < <(git rev-list "$@")

while read -r type sha size path; do
  [ "$type" = blob ] || continue
  if [ -n "$path" ]; then
    lower=$(tr '[:upper:]' '[:lower:]' <<<"$path")
    if grep -qE "$deny" <<<"$lower"; then
      echo "check-no-roms: $path looks like a ROM, archive or game asset" >&2; bad=1; continue
    fi
  fi
  if [ "$size" -gt "$max" ]; then
    echo "check-no-roms: ${path:-$sha} is $((size / 1024 / 1024)) MiB (limit 5 MiB)" >&2; bad=1; continue
  fi
  magic=$(git cat-file blob "$sha" | head -c 4 | od -An -tx1 | tr -d ' \n')
  case $magic in
    80371240 | 37804012 | 40123780)
      echo "check-no-roms: ${path:-$sha} starts with an N64 ROM header" >&2; bad=1 ;;
    504b0304 | 504b0506 | 504b0708 | 1f8b* | fd377a58 | 425a68* | 28b52ffd | 04224d18 | 377abcaf | 52617221)
      echo "check-no-roms: ${path:-$sha} is an archive or compressed file" >&2; bad=1 ;;
  esac
done < <(cut -d' ' -f1 "$list" | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize)' | paste -d' ' - <(awk '{ $1=""; sub(/^ /,""); print }' "$list"))

if [ "$bad" = 1 ]; then
  echo "check-no-roms: refusing. Nothing was pushed." >&2
  exit 1
fi
