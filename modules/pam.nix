{
  lib,
  config,
  ...
}: let
  cfg = config.nixwall.auth;
in {
  options.nixwall.auth = {
    enable = lib.mkEnableOption "NixWall authentication (PAM services)";

    pamService = lib.mkOption {
      type = lib.types.str;
      default = "nixwall-auth";
      description = "Name of the PAM service definition used by NixWall components.";
    };
  };

  config = lib.mkIf cfg.enable {
    security.pam.services.${cfg.pamService} = {
      text = lib.mkDefault ''
        auth     required pam_unix.so
        account  required pam_unix.so
      '';
    };
  };
}
