<h1 align="center">Anchorage</h1>

<p align="center">Install, update and launch the HarbourMasters game ports from Steam OS game mode, with a controller.</p>

> [!WARNING]
> **Certified, artisanal, vibe-coded slop.**
>
> No human has read this code. An AI wrote all of it while a person said "yeah, looks
> good" and pressed Enter a lot.



## Install

```sh
nix run github:DisposableSoftware/anchorage
```

Or as a flake input:

```nix
{
  inputs.anchorage.url = "github:DisposableSoftware/anchorage";

  # NixOS
  imports = [ inputs.anchorage.nixosModules.default ];
  programs.anchorage.enable = true;

  # or home-manager, which can also write the settings
  imports = [ inputs.anchorage.homeManagerModules.default ];
  programs.anchorage = {
    enable = true;
    settings.window.width = 1000;
    keybindings.quit = [ "<Ctrl>q" "<Alt>F4" ];
  };
}
```

## Usage

```sh
anchorage            # open a window
anchorage --help
man anchorage        # every binding and setting
```

Settings live in `~/.config/anchorage/config.ini` and keybindings in
`~/.config/anchorage/keybindings.ini`. Both are created on first start with every
default commented out; remove the `# ` from a line to change it.

## Development

What the app does is written down in [`spec/`](spec/README.md); see
[`CLAUDE.md`](CLAUDE.md) for how changes are made.

```sh
nix develop                 # cargo, clippy, rustfmt, rust-analyzer, GTK 4
cargo run
cargo clippy --all-targets -- -D warnings
cargo test
nix build                   # ./result/bin/anchorage
scripts/manual/headless.sh scripts/manual/smoke.sh
```

## License

MIT, see [LICENSE](LICENSE).

