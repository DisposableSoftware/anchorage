# Tools for scripts/render-steam-art.sh, from the nixpkgs the flake pins, so the
# SVGs and PNGs come out byte for byte the same on every machine.
let
  lock = (builtins.fromJSON (builtins.readFile ../../flake.lock)).nodes.nixpkgs.locked;
  pkgs = import (builtins.fetchTree lock) { };
in
pkgs.mkShellNoCC {
  packages = [
    (pkgs.python3.withPackages (ps: [
      ps.uharfbuzz
      ps.fonttools
    ]))
    pkgs.librsvg
  ];
}
