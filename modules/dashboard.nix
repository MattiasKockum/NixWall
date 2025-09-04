{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.services.dashboard or {};

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
  dashJSON = srvCfg.dashboard or {};

  enabled = dashJSON.enable or (cfg.enable or false);
  port = dashJSON.port   or (cfg.port   or 80);
  content = dashJSON.content or (cfg.content or "<h1>NixWall dashboard</h1>");

  listenZonesJSON = dashJSON.listenZones or [];
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
in {
  options.services.dashboard = {
    enable = lib.mkEnableOption "NixWall dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "Port to listen on.";
    };

    content = lib.mkOption {
      type = lib.types.str;
      default = "<h1>NixWall dashboard</h1>";
      description = "HTML content served at /.";
    };

    listenZones = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Zones to bind to (currently exactly one, e.g. [\"LAN\"]).";
    };
  };

  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = (listenZones != []) && (lib.length listenZones == 1);
        message = "services.dashboard.listenZones must contain exactly one zone for now (e.g., [\"LAN\"]).";
      }
      {
        assertion = listenAddr != null;
        message = "services.dashboard: could not resolve IP for listen zone ${toString listenZone}. Check nixwall.network.addresses.";
      }
      {
        assertion = lib.hasAttr listenZone zoneToIface;
        message = "services.dashboard: listen zone must exist in nixwall.interfaces.";
      }
    ];

    environment.systemPackages = [pkgs.coreutils pkgs.python3];
    environment.etc."demo-index.html".text = content;

    systemd.services.dashboard = {
      description = "NixWall dashboard";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        DynamicUser = true;
        StateDirectory = "dashboard";
        WorkingDirectory = "/var/lib/dashboard";
        ExecStartPre = [
          "${pkgs.coreutils}/bin/install -m0644 /etc/demo-index.html /var/lib/dashboard/index.html"
        ];
        ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString port} --bind ${listenAddr} --directory /var/lib/dashboard";
        Restart = "always";

        AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
        CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];
      };
    };
  };
}
