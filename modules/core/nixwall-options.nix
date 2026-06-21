{ lib, config, ... }: {
  options.nixwall = {
    enable = lib.mkEnableOption "NixWall firewall";

    appliance.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable appliance mode. Activates the API, dashboard, git integration,
        TLS, PAM, seed-config, and boot configuration. Use this when NixWall
        owns the machine entirely. Leave disabled when adding NixWall to an
        existing NixOS configuration.
      '';
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the NixWall JSON configuration file.
        Required unless nixwall.config is set inline.
      '';
      example = "/etc/nixos/nixwall-config.json";
    };

    config = lib.mkOption {
      type = with lib.types; nullOr (attrsOf anything);
      default = null;
      description = "Inline configuration as Nix attrs. Overrides configFile. Useful in tests.";
    };

    parsedConfig = lib.mkOption {
      type = with lib.types; attrsOf anything;
      readOnly = true;
      internal = true;
      description = "Parsed nixwall configuration. Do not set this directly.";
      default =
        if config.nixwall.config != null then
          config.nixwall.config
        else if config.nixwall.configFile != null then
          lib.importJSON config.nixwall.configFile
        else
          { };
    };
  };

  config = lib.mkIf config.nixwall.enable {
    assertions = [
      {
        assertion = config.nixwall.config != null || config.nixwall.configFile != null;
        message = "nixwall: you must set either nixwall.config (inline) or nixwall.configFile (path to JSON).";
      }
    ];
  };
}
