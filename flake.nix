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
      packages = forAll (
        pkgs:
        {
          default = pkgs.callPackage ./nix/package.nix { };
        }
        # INT-25: the AppImage uses the prebuilt x86_64 export template.
        // nixpkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
          appimage = pkgs.callPackage ./nix/appimage.nix { };
        }
      );

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
        # INT-28, INT-29, INT-33, INT-34: the SteamOS installer against fake Steam folders and
        # a fake GitHub on 127.0.0.1. The installer refuses anything but x86_64.
        // nixpkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
          steam-install =
            pkgs.runCommand "anchorage-steam-install"
              {
                nativeBuildInputs = with pkgs; [
                  (python3.withPackages (ps: [ ps.vdf ]))
                  shellcheck
                  curl
                  desktop-file-utils
                ];
              }
              ''
                cp -r ${./scripts} scripts && cp -r ${./data} data && chmod -R u+w scripts data
                bash scripts/manual/steam-install.sh
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
