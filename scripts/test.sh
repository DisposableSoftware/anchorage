#!/usr/bin/env bash
# Runs the unit and spec conformance tests headless. Run inside `nix develop`, from anywhere.
# Godot prints script errors without failing, so any "SCRIPT ERROR" or "Parse Error"
# in the output fails the run too.
set -uo pipefail
cd "$(dirname "$0")/../app"
home=$(mktemp -d); trap 'rm -rf "$home"' EXIT
out=$(HOME=$home XDG_CONFIG_HOME=$home/config XDG_CACHE_HOME=$home/cache XDG_DATA_HOME=$home/data \
  godot --headless --path . -s tests/run.gd 2>&1)
status=$?
echo "$out"
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script' <<<"$out"; then
  echo "test.sh: script errors above" >&2; status=1
fi
exit $status
