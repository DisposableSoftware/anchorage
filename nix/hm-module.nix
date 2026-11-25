self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.anchorage;
  ini = pkgs.formats.ini { listToValue = lib.concatMapStringsSep ";" toString; };
in
{
  options.programs.anchorage = {
    enable = lib.mkEnableOption "Anchorage";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "anchorage.packages.\${system}.default";
    };
    settings = lib.mkOption {
      inherit (ini) type;
      default = { };
      example = {
        appearance.flavor = "latte";
        appearance.accent = "blue";
        roms.directory = "~/Games/n64";
        ports.check_updates = false;
      };
      description = "Written to $XDG_CONFIG_HOME/anchorage/config.ini. A list is joined with ';', so roms.directory can name several folders.";
    };
    keybindings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = {
        quit = [
          "Ctrl+Q"
          "Alt+F4"
        ];
        accept = [
          "Enter"
          "Pad:A"
        ];
      };
      description = "Binding name to keys, written to $XDG_CONFIG_HOME/anchorage/keybindings.ini. An empty list unbinds it; names are in the example file.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    xdg.configFile."anchorage/config.ini" = lib.mkIf (cfg.settings != { }) {
      source = ini.generate "anchorage-config.ini" cfg.settings;
    };
    xdg.configFile."anchorage/keybindings.ini" = lib.mkIf (cfg.keybindings != { }) {
      source = ini.generate "anchorage-keybindings.ini" { inherit (cfg) keybindings; };
    };
  };
}
