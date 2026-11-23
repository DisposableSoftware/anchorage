{
  description = "Anchorage — a controller-first launcher for the HarbourMasters game ports";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (pkgs: {
        default = pkgs.callPackage ./nix/package.nix { };
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            godot
            gdtoolkit_4
          ];
        };
      });

      # INT-24: `nix flake check` runs the tests (by building the package), gdlint and gdformat.
      checks = forAll (
        pkgs:
        let
          pkg = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        in
        {
          tests = pkg;
          gdscript = pkgs.runCommand "anchorage-gdscript" { nativeBuildInputs = [ pkgs.gdtoolkit_4 ]; } ''
            export HOME=$TMPDIR
            cp -r ${./app} app && chmod -R u+w app && cd app
            gdlint src tests
            gdformat --check src tests
            touch $out
          '';
        }
      );

      formatter = forAll (pkgs: pkgs.nixfmt);

      overlays.default = final: _: { anchorage = final.callPackage ./nix/package.nix { }; };

      nixosModules.default = import ./nix/nixos-module.nix self;
      homeManagerModules.default = import ./nix/hm-module.nix self;
    };
}
