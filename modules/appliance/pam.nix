{ lib, config, ... }:
let
  cfg = config.nixwall.appliance.auth;
in
{
  options.nixwall.appliance.auth = {
    enable = lib.mkEnableOption "NixWall PAM authentication";

    pamService = lib.mkOption {
      type = lib.types.str;
      default = "nixwall-auth";
    };
  };

  config = lib.mkIf (config.nixwall.enable && config.nixwall.appliance.enable && cfg.enable) {
    security.pam.services.${cfg.pamService}.text = ''
      auth     required pam_unix.so
      account  required pam_unix.so
    '';
  };
}
