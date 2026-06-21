{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.nixwall.appliance.dashboard;
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
in
{
  options.nixwall.appliance.dashboard = {
    enable = lib.mkEnableOption "NixWall dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 80;
    };

    listenZone = lib.mkOption {
      type = lib.types.str;
      default = "LAN";
    };
  };

  config = lib.mkIf (config.nixwall.enable && config.nixwall.appliance.enable && cfg.enable) {
    assertions = [
      {
        assertion = lib.hasAttr cfg.listenZone zoneToIface;
        message = "nixwall.appliance.dashboard.listenZone \"${cfg.listenZone}\" must exist in your nixwall interfaces config.";
      }
      {
        assertion = listenAddr != null;
        message = "nixwall.appliance.dashboard: could not resolve IP for zone \"${cfg.listenZone}\".";
      }
    ];

    systemd.services.nixwall-dashboard = {
      description = "NixWall dashboard";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        DynamicUser = true;
        StateDirectory = "nixwall-dashboard";
        WorkingDirectory = "/var/lib/nixwall-dashboard";
        Restart = "always";

        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];

        ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString cfg.port} --bind ${listenAddr} --directory /var/lib/nixwall-dashboard";
      };
    };
  };
}
