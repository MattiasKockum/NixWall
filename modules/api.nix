{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.services.api or {};

  nw = config.nixwall or {};
  parsed =
    if (nw.config or null) != null
    then nw.config
    else if (nw.configFile or null) != null
    then lib.importJSON nw.configFile
    else {};

  zoneToIface = parsed.interfaces or {};
  addresses = (parsed.network or {}).addresses or {};
  srvCfg = parsed.services or {};
  apiJSON = srvCfg.api or {};

  enabled = apiJSON.enable or (cfg.enable or false);
  port = apiJSON.port or cfg.port;

  listenZonesJSON = apiJSON.listenZones or [];
  listenZonesOpt = cfg.listenZones or [];
  listenZones =
    if listenZonesJSON != []
    then listenZonesJSON
    else listenZonesOpt;

  listenZone =
    if listenZones == []
    then null
    else lib.head listenZones;

  getIPForZone = zone: let
    cidr = addresses.${zone} or null;
  in
    if cidr == null
    then null
    else lib.head (lib.splitString "/" cidr);

  listenAddr =
    if listenZone == null
    then null
    else getIPForZone listenZone;

  nixwallApiPkg = pkgs.callPackage ../pkgs/nixwall-api.nix {};
in {
  options.services.api = {
    enable = lib.mkEnableOption "NixWall API (FastAPI)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on (overridden by JSON when set).";
    };

    listenZones = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Zones to bind to (exactly one, e.g. [\"LAN\"]).";
    };
  };

  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = (listenZones != []) && (lib.length listenZones == 1);
        message = "services.api.listenZones must contain exactly one zone for now (e.g., [\"LAN\"]).";
      }
      {
        assertion = lib.hasAttr listenZone zoneToIface;
        message = "services.api: listen zone must exist in nixwall.interfaces.";
      }
      {
        assertion = listenAddr != null;
        message = "services.api: could not resolve IP for listen zone ${toString listenZone}. Check nixwall.network.addresses.";
      }
    ];

    systemd.services.nixwall-api = {
      description = "NixWall API (FastAPI)";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      path = [
        pkgs.iproute2
        pkgs.git
        pkgs.systemd
        pkgs.nix
        pkgs.nixos-rebuild
      ];

      serviceConfig = {
        Type = "simple";
        User = "root";
        Group = "root";
        WorkingDirectory = "/etc/nixos";

        Environment = [
          "NW_API_HOST=${listenAddr}"
          "NW_API_PORT=${toString port}"
          "NW_CONFIG_PATH=/etc/nixos/config.json"
          "NW_REPO_DIR=/etc/nixos"
          "NW_FLAKE=/etc/nixos"
          "PYTHONUNBUFFERED=1"
        ];

        ExecStart = "${nixwallApiPkg}/bin/nixwall-api";
        Restart = "always";

        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
}
