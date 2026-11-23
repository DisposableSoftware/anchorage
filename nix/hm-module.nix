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
        window.width = 1000;
        view.greeting = "Hi";
      };
      description = "Written to $XDG_CONFIG_HOME/anchorage/config.ini.";
    };
    keybindings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = {
        quit = [
          "<Ctrl>q"
          "<Alt>F4"
        ];
        new-window = [ ];
      };
      description = "Binding name to keys, written to $XDG_CONFIG_HOME/anchorage/keybindings.ini. An empty list unbinds it; see anchorage(1) for the names.";
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
