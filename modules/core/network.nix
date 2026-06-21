{ lib, config, ... }:
let
  parsed = config.nixwall.parsedConfig;
  net = parsed.network or { };
  addrs = net.addresses or { };
  dns = net.dns or [ ];
  gateway = net.gateway or null;
  hostname = net.hostname or "nixwall";

  zoneToIface = parsed.interfaces or { };
  wanIface = zoneToIface.WAN or null;

  splitCIDR =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    {
      address = lib.elemAt parts 0;
      prefixLength = lib.toInt (lib.elemAt parts 1);
    };

  isV6Addr = addr: builtins.match ".*:.*" addr != null;

  ifaceAddrs = lib.foldl' (
    acc: zone:
    let
      ifc = zoneToIface.${zone} or null;
      cidr = addrs.${zone} or null;
    in
    if ifc == null || cidr == null then
      acc
    else
      let
        ip = splitCIDR cidr;
        v = acc.${ifc} or { };
        new =
          if isV6Addr ip.address then
            v
            // {
              ipv6 = (v.ipv6 or { }) // {
                addresses = (v.ipv6.addresses or [ ]) ++ [ ip ];
              };
            }
          else
            v
            // {
              ipv4 = (v.ipv4 or { }) // {
                addresses = (v.ipv4.addresses or [ ]) ++ [ ip ];
              };
            };
      in
      acc // { ${ifc} = new; }
  ) { } (lib.attrNames addrs);

  interfacesConfig = lib.mapAttrs (_: v: {
    useDHCP = false;
    ipv4.addresses = lib.mkForce (v.ipv4.addresses or [ ]);
    ipv6.addresses = lib.mkForce (v.ipv6.addresses or [ ]);
  }) ifaceAddrs;
in
{
  config = lib.mkIf config.nixwall.enable {
    assertions = [
      {
        assertion = lib.all (zone: lib.hasAttr zone zoneToIface) (lib.attrNames addrs);
        message = "nixwall: every network.addresses <ZONE> must exist in interfaces mapping.";
      }
      {
        assertion = lib.all (
          zone:
          let
            s = splitCIDR addrs.${zone};
          in
          s.prefixLength >= 0 && s.prefixLength <= 128
        ) (lib.attrNames addrs);
        message = "nixwall: each CIDR in network.addresses must have a valid prefix length (0–128).";
      }
      {
        assertion = builtins.isList dns && lib.all lib.isString dns;
        message = "nixwall: network.dns must be a list of strings.";
      }
      {
        assertion = gateway == null || wanIface != null;
        message = "nixwall: network.gateway is set but interfaces.WAN is missing.";
      }
    ];

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv6.conf.default.forwarding" = 1;
    };

    networking = {
      useNetworkd = true;
      networkmanager.enable = false;
      useDHCP = false;
      hostName = hostname;
      nameservers = dns;
      enableIPv6 = true;
      tempAddresses = "disabled";
      interfaces = interfacesConfig;

      defaultGateway = lib.mkIf (gateway != null && !(isV6Addr gateway)) {
        address = gateway;
        interface = wanIface;
      };
      defaultGateway6 = lib.mkIf (gateway != null && isV6Addr gateway) {
        address = gateway;
        interface = wanIface;
      };
    };
  };
}
