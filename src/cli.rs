use gtk::glib;
use std::ffi::OsString;

/// What `--help` or `--version` prints (`INT-30`, `INT-31`). GLib's own help would
/// say "Usage: io.github.DisposableSoftware.Anchorage", because the prgname must stay the app ID.
pub fn early(args: impl IntoIterator<Item = OsString>) -> Option<String> {
    for arg in args.into_iter().skip(1) {
        match arg.to_str() {
            Some("--") => return None,
            Some("-h" | "--help") => return Some(help()),
            Some("-V" | "--version") => return Some(version()),
            _ => {}
        }
    }
    None
}

fn version() -> String {
    format!("anchorage {}\n", env!("CARGO_PKG_VERSION"))
}

fn help() -> String {
    let dir = glib::user_config_dir().join("anchorage");
    let config = dir.join("config.ini").display().to_string();
    let keys = dir.join("keybindings.ini").display().to_string();
    let w = config.chars().count().max(keys.chars().count());
    format!(
        "\
Usage: anchorage [OPTION…]

Opens a Anchorage window. If Anchorage is already running, the window opens in it.

Options:
  -h, --help     Show this help and exit
  -V, --version  Show the version and exit

Files:
  {config:<w$}  settings
  {keys:<w$}  keybindings

See anchorage(1) for the keybindings and every setting.
",
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(args: &[&str]) -> Option<String> {
        early(
            std::iter::once("anchorage")
                .chain(args.iter().copied())
                .map(OsString::from),
        )
    }

    #[test]
    fn help_and_version() {
        let help = run(&["--help"]).unwrap();
        assert!(help.starts_with("Usage: anchorage [OPTION…]\n"));
        for part in [
            "--help",
            "--version",
            "config.ini",
            "keybindings.ini",
            "anchorage(1)",
        ] {
            assert!(help.contains(part), "help lacks {part}");
        }
        assert_eq!(run(&["x", "-h"]), Some(help));
        assert_eq!(
            run(&["-V"]).unwrap(),
            format!("anchorage {}\n", env!("CARGO_PKG_VERSION"))
        );
        assert_eq!(run(&["--version"]), run(&["-V"]));
        assert_eq!(run(&[]), None);
        assert_eq!(run(&["--", "--help"]), None);
    }
}
