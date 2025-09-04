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
  dhcpCfg = parsed.dhcp or {};
  subnets = dhcpCfg.subnets or {};

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

  parseRange = r: let
    parts = lib.splitString "-" r;
  in
    if (lib.length parts) == 2
    then {
      start = lib.elemAt parts 0;
      end = lib.elemAt parts 1;
    }
    else throw "nixwall.dhcp: range '${r}' must be 'START-END'";

  leaseStr = secs: "${toString secs}s";

  dhcpIfaces = lib.unique (lib.flatten (lib.mapAttrsToList (
      zone: _: let ifc = zoneToIface.${zone} or null; in lib.optional (ifc != null) ifc
    )
    subnets));

  dhcpRanges = lib.flatten (lib.mapAttrsToList (
      zone: s: let
        ifc = zoneToIface.${zone} or null;
        lanIP = ipOfZone zone;
        r = parseRange s.range;
      in
        lib.optionals (ifc != null && lanIP != null) [
          "${r.start},${r.end},${leaseStr (s.leaseSeconds or 86400)}"
        ]
    )
    subnets);
in {
  config = lib.mkIf (subnets != {}) {
    assertions = [
      {
        assertion = lib.all (zone: lib.hasAttr zone zoneToIface) (lib.attrNames subnets);
        message = "nixwall.dhcp: every dhcp.subnets <ZONE> must exist in interfaces mapping.";
      }
      {
        assertion = lib.all (zone: lib.hasAttr zone addrs) (lib.attrNames subnets);
        message = "nixwall.dhcp: every dhcp.subnets <ZONE> must have a matching network.addresses entry.";
      }
    ];

    services.dnsmasq.enable = true;
    services.dnsmasq.settings = {
      interface = dhcpIfaces;
      bind-interfaces = true;
      dhcp-authoritative = true;
      dhcp-range = dhcpRanges;
      log-dhcp = true;
    };

    networking.firewall.enable = true;
    networking.firewall.interfaces = lib.listToAttrs (map
      (ifc: {
        name = ifc;
        value = {allowedUDPPorts = [67 68];};
      })
      dhcpIfaces);
  };
}
