#!/usr/bin/env bash
# Spec: PROD-14. Proves scripts/check-no-roms.sh stops ROMs: builds throwaway repos in a
# temp dir and checks that a ROM by name, a ROM by header under an innocent name, and a
# large file are refused, and that clean files pass.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (expected $2, got $3)"; fails=$((fails + 1)); fi; }
newrepo() { rm -rf "$T/r"; git init -q "$T/r"; git -C "$T/r" config user.email t@t; git -C "$T/r" config user.name t; }
run() { (cd "$T/r" && "$here/scripts/check-no-roms.sh" HEAD >/dev/null 2>&1; echo $?); }
commit() { git -C "$T/r" add -A && git -C "$T/r" commit -qm x; }

newrepo; echo hello >"$T/r/readme.txt"; commit
check "clean repo passes" 0 "$(run)"
newrepo; printf '\x80\x37\x12\x40rest' >"$T/r/Zelda.z64"; commit
check "ROM by name" 1 "$(run)"
newrepo; printf '\x80\x37\x12\x40rest' >"$T/r/notes.txt"; commit
check "z64 header under an innocent name" 1 "$(run)"
newrepo; printf '\x37\x80\x40\x12rest' >"$T/r/a.dat"; commit
check "v64 header" 1 "$(run)"
newrepo; printf '\x40\x12\x37\x80rest' >"$T/r/b.dat"; commit
check "n64 header" 1 "$(run)"
newrepo; head -c 6000000 /dev/zero >"$T/r/big.dat"; commit
check "file over 5 MiB" 1 "$(run)"
newrepo; echo x >"$T/r/Game.ZIP"; commit
check "upper-case archive extension" 1 "$(run)"
newrepo; echo x >"$T/r/oot.o2r"; commit
check "generated game archive" 1 "$(run)"
[ "$fails" = 0 ]
