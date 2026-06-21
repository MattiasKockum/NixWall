{ lib, config, ... }:
let
  parsed = config.nixwall.parsedConfig;
  zoneToIface = parsed.interfaces or { };
  addrs = (parsed.network or { }).addresses or { };
  subnets = (parsed.dhcp or { }).subnets or { };

  ipOfZone =
    zone:
    let
      cidr = addrs.${zone} or null;
    in
    if cidr == null then null else lib.head (lib.splitString "/" cidr);

  parseRange =
    r:
    let
      parts = lib.splitString "-" r;
    in
    if lib.length parts == 2 then
      {
        start = lib.elemAt parts 0;
        end = lib.elemAt parts 1;
      }
    else
      throw "nixwall.dhcp: range '${r}' must be 'START-END'";

  dhcpIfaces = lib.unique (
    lib.flatten (
      lib.mapAttrsToList (
        zone: _:
        let
          ifc = zoneToIface.${zone} or null;
        in
        lib.optional (ifc != null) ifc
      ) subnets
    )
  );

  dhcpRanges = lib.flatten (
    lib.mapAttrsToList (
      zone: s:
      let
        ifc = zoneToIface.${zone} or null;
        lanIP = ipOfZone zone;
        r = parseRange s.range;
      in
      lib.optionals (ifc != null && lanIP != null) [
        "${r.start},${r.end},${toString (s.leaseSeconds or 86400)}s"
      ]
    ) subnets
  );

  routerOptions = lib.concatMap (
    ifc:
    let
      zone = lib.findFirst (z: zoneToIface.${z} or null == ifc) null (lib.attrNames zoneToIface);
      ip = if zone != null then ipOfZone zone else null;
    in
    lib.optional (ip != null) "3,${ip}"
  ) dhcpIfaces;
in
{
  config = lib.mkIf (config.nixwall.enable && subnets != { }) {
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

    services.dnsmasq = {
      enable = true;
      settings = {
        interface = dhcpIfaces;
        bind-interfaces = true;
        dhcp-authoritative = true;
        dhcp-range = dhcpRanges;
        log-dhcp = true;
      }
      // lib.optionalAttrs (routerOptions != [ ]) {
        dhcp-option = routerOptions;
      };
    };
  };
}
