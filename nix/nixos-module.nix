self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.anchorage;
in
{
  options.programs.anchorage = {
    enable = lib.mkEnableOption "Anchorage";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "anchorage.packages.\${system}.default";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
