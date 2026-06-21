{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.nixwall.appliance.api;
  parsed = config.nixwall.parsedConfig;

  zoneToIface = parsed.interfaces or { };
  addresses = (parsed.network or { }).addresses or { };

  getIPForZone =
    zone:
    let
      cidr = addresses.${zone} or null;
    in
    if cidr == null then null else lib.head (lib.splitString "/" cidr);

  listenAddr = getIPForZone cfg.listenZone;

  nixwallApiPkg = pkgs.callPackage ../../pkgs/nixwall-api.nix { };
in
{
  options.nixwall.appliance.api = {
    enable = lib.mkEnableOption "NixWall API";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
    };

    listenZone = lib.mkOption {
      type = lib.types.str;
      default = "LAN";
      description = "Zone to bind the API to.";
    };
  };

  config = lib.mkIf (config.nixwall.enable && config.nixwall.appliance.enable && cfg.enable) {
    assertions = [
      {
        assertion = lib.hasAttr cfg.listenZone zoneToIface;
        message = "nixwall.appliance.api.listenZone \"${cfg.listenZone}\" must exist in your nixwall interfaces config.";
      }
      {
        assertion = listenAddr != null;
        message = "nixwall.appliance.api: could not resolve IP for zone \"${cfg.listenZone}\".";
      }
    ];

    systemd.services.nixwall-api = {
      description = "NixWall API";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "nixwall-tls.service"
      ];
      wants = [
        "network-online.target"
        "nixwall-tls.service"
      ];

      path = with pkgs; [
        iproute2
        git
        systemd
        nix
        nixos-rebuild
      ];

      serviceConfig = {
        Type = "simple";
        User = "root";
        Group = "root";
        WorkingDirectory = "/etc/nixos";
        Restart = "always";
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;

        Environment = [
          "NW_API_HOST=${listenAddr}"
          "NW_API_PORT=${toString cfg.port}"
          "NW_CONFIG_PATH=${
            if config.nixwall.configFile != null then
              toString config.nixwall.configFile
            else
              "/etc/nixos/config.json"
          }"
          "NW_REPO_DIR=/etc/nixos"
          "NW_FLAKE=/etc/nixos"
          "NW_API_TLS_CERT=${config.nixwall.appliance.tls.certFile}"
          "NW_API_TLS_KEY=${config.nixwall.appliance.tls.keyFile}"
          "NW_PAM_SERVICE=${config.nixwall.appliance.auth.pamService}"
        ];

        ExecStart = "${nixwallApiPkg}/bin/nixwall-api";
      };
    };
  };
}
