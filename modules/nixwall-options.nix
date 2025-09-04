{
  lib,
  self,
  ...
}: {
  options.nixwall = {
    config = lib.mkOption {
      type = with lib.types; nullOr (attrsOf anything);
      default = null;
      description = "Inline JSON (as Nix attrs) to override the file (useful in tests).";
    };
    configFile = lib.mkOption {
      type = lib.types.path;
      default = self + "/config.json";
      description = "Path to the JSON config file (e.g., ${self}/config.json).";
    };
  };
}
