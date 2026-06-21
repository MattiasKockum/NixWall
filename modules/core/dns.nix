{ lib, config, ... }:
let
  parsed = config.nixwall.parsedConfig;
  zoneToIface = parsed.interfaces or { };
  addrs = (parsed.network or { }).addresses or { };
  dnsCfg = (parsed.services or { }).dns or { };

  enable = dnsCfg.enable or false;
  port = dnsCfg.port or 53;
  records = dnsCfg.dict or { };
  listenZones = dnsCfg.listenZones or [ "LAN" ];
  cacheSize = dnsCfg.cacheSize or 1000;

  ipOfZone =
    zone:
    let
      cidr = addrs.${zone} or null;
    in
    if cidr == null then null else lib.head (lib.splitString "/" cidr);

  ifaceList = lib.filter (x: x != null) (map (z: zoneToIface.${z} or null) listenZones);
  selfDnsIPs = lib.filter (x: x != null) (map ipOfZone listenZones);
  addressLines = lib.mapAttrsToList (host: ip: "/${host}/${ip}") records;
  hasLanNames = lib.any (n: lib.hasSuffix ".lan" n) (lib.attrNames records);
in
{
  config = lib.mkIf (config.nixwall.enable && enable) {
    assertions = [
      {
        assertion = ifaceList != [ ];
        message = "nixwall.services.dns: no interface found for listenZones = ${toString listenZones}.";
      }
      {
        assertion = builtins.isAttrs records && lib.all lib.isString (lib.attrValues records);
        message = "nixwall.services.dns.dict must be { hostname -> ip } strings.";
      }
    ];

    services.dnsmasq = {
      enable = true;
      settings = lib.mkMerge [
        {
          interface = ifaceList;
          bind-interfaces = true;
          inherit port;
          domain-needed = true;
          bogus-priv = true;
          cache-size = cacheSize;
          log-queries = false;
        }
        (lib.mkIf (addressLines != [ ]) { address = addressLines; })
        (lib.mkIf hasLanNames { local = [ "/lan/" ]; })
        (lib.mkIf (selfDnsIPs != [ ]) { dhcp-option = map (ip: "6,${ip}") selfDnsIPs; })
      ];
    };
  };
}
