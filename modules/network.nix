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
  dns = net.dns or [];
  gateway = net.gateway or null;
  hostname = net.hostname or "nixwall";

  splitCIDR = cidr: let
    parts = lib.splitString "/" cidr;
  in {
    address = lib.elemAt parts 0;
    prefixLength = lib.toInt (lib.elemAt parts 1);
  };

  isV6 = addr: builtins.match ".*:.*" addr != null;

  ifaceAddrs =
    lib.foldl'
    (
      acc: zone: let
        ifc = zoneToIface.${zone} or null;
        cidr = addrs.${zone} or null;
      in
        if ifc == null || cidr == null
        then acc
        else let
          ip = splitCIDR cidr;
          v = acc.${ifc} or {};
          new =
            if isV6 ip.address
            then v // {ipv6 = (v.ipv6 or {}) // {addresses = (v.ipv6.addresses or []) ++ [ip];};}
            else v // {ipv4 = (v.ipv4 or {}) // {addresses = (v.ipv4.addresses or []) ++ [ip];};};
        in
          acc // {${ifc} = new;}
    )
    {}
    (lib.attrNames addrs);

  interfacesConfig =
    lib.mapAttrs (_ifc: v: {
      useDHCP = false;
      ipv4.addresses = lib.mkForce (v.ipv4.addresses or []);
      ipv6.addresses = lib.mkForce (v.ipv6.addresses or []);
    })
    ifaceAddrs;

  wanIface = zoneToIface.WAN or null;

  validPrefix = p: p >= 0 && p <= 128;
in {
  config = {
    assertions = [
      {
        assertion = builtins.isAttrs parsed;
        message = "nixwall: parsed config must be a JSON object.";
      }
      {
        assertion =
          lib.all (zone: lib.hasAttr zone zoneToIface) (lib.attrNames addrs);
        message = "nixwall: every network.addresses <ZONE> must exist in interfaces mapping.";
      }
      {
        assertion =
          lib.all
          (
            zone: let
              cidr = addrs.${zone};
              s = splitCIDR cidr;
            in
              validPrefix s.prefixLength
          )
          (lib.attrNames addrs);
        message = "nixwall: each CIDR in network.addresses must have a valid prefix (0..128).";
      }
      {
        assertion = builtins.isList dns && lib.all lib.isString dns;
        message = "nixwall: network.dns must be a list of strings.";
      }
      {
        assertion = gateway == null || wanIface != null;
        message = "nixwall: network.gateway is set but interfaces.WAN is missing; define WAN→<iface>.";
      }
    ];

    networking = {
      useNetworkd = true;
      networkmanager.enable = false;
      useDHCP = false;

      hostName = hostname;
      nameservers = dns;

      defaultGateway = lib.mkIf (gateway != null && !(builtins.match ".*:.*" gateway != null)) {
        address = gateway;
        interface = zoneToIface.WAN or null;
      };
      defaultGateway6 = lib.mkIf (gateway != null && (builtins.match ".*:.*" gateway != null)) {
        address = gateway;
        interface = zoneToIface.WAN or null;
      };

      interfaces = interfacesConfig;

      enableIPv6 = true;

      tempAddresses = "disabled";
    };
  };
}
