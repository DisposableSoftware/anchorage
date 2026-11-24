#!/usr/bin/env bash
# Runs the unit and spec conformance tests headless. Run inside `nix develop`, from anywhere.
# Godot prints script and engine errors without failing, so the run also fails on any
# "SCRIPT ERROR", "Parse Error", "Failed to load script", "Unicode parsing error" or
# engine "ERROR:" line, except the engine errors that tests provoke on purpose (ALLOWED).
set -uo pipefail
cd "$(dirname "$0")/../app"
home=$(mktemp -d); trap 'rm -rf "$home"' EXIT
test_output=$(env HOME="$home" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" \
  XDG_DATA_HOME="$home/data" XDG_STATE_HOME="$home/state" \
  ANCHORAGE_TEST_SENTINEL="a=b c" \
  godot --headless --path . -s tests/run.gd 2>&1)
status=$?
echo "$test_output"
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|Unicode parsing error' <<<"$test_output"; then
  echo "test.sh: script errors above" >&2; status=1
fi
# An engine error is followed by its "at:" line and a GDScript backtrace. It is allowed only
# when that backtrace runs through one of these tests, which hand Godot broken input on
# purpose (a truncated PNG, a folder that can't be created).
ALLOWED='test_art::test_a_truncated_image_is_deleted|test_config::test_starts_with_defaults_when_the_files_cant_be_created'
unexpected=$(awk -v allowed="$ALLOWED" '
  function flush() {
    if (block != "" && !ok) { print block }
    block = ""; ok = 0
  }
  /^ERROR: / { flush(); block = $0; next }
  block != "" && /^ +/ {
    block = block "\n" $0
    if (match($0, /\] [a-z_0-9]+ \(res:\/\/tests\/[a-z_0-9]+\.gd/)) {
      split(substr($0, RSTART + 2, RLENGTH - 2), part, " ")
      file = $0; sub(/.*res:\/\/tests\//, "", file); sub(/\.gd.*/, "", file)
      if ((file "::" part[1]) ~ ("^(" allowed ")$")) { ok = 1 }
    }
    next
  }
  { flush() }
  END { flush() }
' <<<"$test_output")
if [ -n "$unexpected" ]; then
  echo "test.sh: unexpected engine errors:" >&2
  echo "$unexpected" >&2
  status=1
fi
exit $status
