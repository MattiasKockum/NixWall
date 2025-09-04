{
  lib,
  config,
  ...
}: let
  cfg = config.nixwall;

  parsed =
    if cfg.config != null
    then cfg.config
    else lib.importJSON cfg.configFile;

  zoneToIface = parsed.interfaces or {};
  net = parsed.network or {};
  addrs = net.addresses or {};
  dnsCfg = (parsed.services or {}).dns or {};
  enable = dnsCfg.enable or false;
  port = dnsCfg.port   or 53;
  records = dnsCfg.dict   or {};
  listenZones = dnsCfg.listenZones or ["LAN"];
  cacheSize = dnsCfg.cacheSize or 1000;

  splitCIDR = cidr: let
    p = lib.splitString "/" cidr;
  in {
    address = lib.elemAt p 0;
    prefixLength = lib.toInt (lib.elemAt p 1);
  };

  ipOfZone = zone: let
    cidr = addrs.${zone} or null;
  in
    if cidr == null
    then null
    else (splitCIDR cidr).address;

  ifaceList =
    lib.filter (x: x != null)
    (map (z: zoneToIface.${z} or null) listenZones);

  selfDnsIPs = lib.filter (x: x != null) (map ipOfZone listenZones);

  addressLines = lib.mapAttrsToList (host: ip: "/${host}/${ip}") records;

  firewallIfaceMap = lib.listToAttrs (map (ifc: {
      name = ifc;
      value = {
        allowedUDPPorts = [port];
        allowedTCPPorts = [port];
      };
    })
    ifaceList);

  dhcpDnsOptions = map (ip: "6,${ip}") selfDnsIPs;

  hasLanNames = lib.any (n: lib.hasSuffix ".lan" n) (lib.attrNames records);
in {
  config = lib.mkIf enable {
    assertions = [
      {
        assertion = ifaceList != [];
        message = "nixwall.services.dns: No interface found for listenZones=${toString listenZones}.";
      }
      {
        assertion =
          builtins.isAttrs records
          && lib.all lib.isString (lib.attrValues records);
        message = "nixwall.services.dns.dict must be { hostname -> ip } strings.";
      }
    ];

    services.dnsmasq.enable = true;

    services.dnsmasq.settings = lib.mkMerge [
      {
        interface = ifaceList;
        bind-interfaces = true;
        inherit port;
        domain-needed = true;
        bogus-priv = true;
        cache-size = cacheSize;
        log-queries = false;
      }

      (lib.mkIf (addressLines != []) {address = addressLines;})

      (lib.mkIf hasLanNames {local = ["/lan/"];})

      (lib.mkIf (dhcpDnsOptions != []) {
        "dhcp-option" = dhcpDnsOptions;
      })
    ];

    networking.firewall.enable = true;
    networking.firewall.interfaces = lib.mkMerge [firewallIfaceMap];
  };
}
