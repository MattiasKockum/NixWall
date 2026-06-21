{ lib, config, ... }:
let
  parsed = config.nixwall.parsedConfig;
  zoneToIface = parsed.interfaces or { };
  rules = (parsed.firewall or { }).rules or [ ];

  toPortList =
    p:
    if p == null then
      [ ]
    else if builtins.isList p then
      map (x: if builtins.isInt x then x else lib.toInt x) p
    else if builtins.isInt p then
      [ p ]
    else
      [ (lib.toInt p) ];

  isFW = t: t == "FW" || t == "fw" || t == "Firewall" || t == "firewall" || t == "self";

  portStr = ports: "{ ${lib.concatStringsSep ", " (map toString ports)} }";

  mkInputRules =
    r:
    let
      proto = lib.toLower (r.proto or "any");
      ports = toPortList (r.ports or [ ]);
      inIface = zoneToIface.${r.from or ""} or null;
    in
    if !(isFW (r.to or "")) || inIface == null then
      [ ]
    else if ports == [ ] then
      lib.optional (proto == "tcp" || proto == "any") "iifname \"${inIface}\" tcp accept"
      ++ lib.optional (proto == "udp" || proto == "any") "iifname \"${inIface}\" udp accept"
    else
      lib.optional (
        proto == "tcp" || proto == "any"
      ) "tcp dport ${portStr ports} iifname \"${inIface}\" accept"
      ++ lib.optional (
        proto == "udp" || proto == "any"
      ) "udp dport ${portStr ports} iifname \"${inIface}\" accept";

  mkForwardRules =
    r:
    let
      proto = lib.toLower (r.proto or "any");
      ports = toPortList (r.ports or [ ]);
      inIface = zoneToIface.${r.from or ""} or null;
      outIface = zoneToIface.${r.to or ""} or null;
    in
    if isFW (r.to or "") || inIface == null || outIface == null then
      [ ]
    else if ports == [ ] then
      [ "iifname \"${inIface}\" oifname \"${outIface}\" accept" ]
    else
      lib.optional (
        proto == "tcp" || proto == "any"
      ) "tcp dport ${portStr ports} iifname \"${inIface}\" oifname \"${outIface}\" accept"
      ++ lib.optional (
        proto == "udp" || proto == "any"
      ) "udp dport ${portStr ports} iifname \"${inIface}\" oifname \"${outIface}\" accept";

  masqueradeZones = (parsed.nat or { }).masquerade or [ ];
  wanIface = zoneToIface.WAN or null;
  natRules = lib.concatMap (
    zone:
    let
      inIface = zoneToIface.${zone} or null;
    in
    lib.optional (
      inIface != null && wanIface != null
    ) "iifname \"${inIface}\" oifname \"${wanIface}\" masquerade"
  ) masqueradeZones;

  dhcpSubnets = (parsed.dhcp or { }).subnets or { };
  dhcpIfaces = lib.unique (
    lib.filter (x: x != null) (lib.mapAttrsToList (zone: _: zoneToIface.${zone} or null) dhcpSubnets)
  );

  dnsEnabled = (parsed.services or { }).dns.enable or false;
  dnsZones = (parsed.services or { }).dns.listenZones or [ "LAN" ];
  dnsIfaces = lib.filter (x: x != null) (map (z: zoneToIface.${z} or null) dnsZones);

  lanIfaces = lib.filter (ifc: ifc != wanIface && ifc != null) (lib.attrValues zoneToIface);

  implicitRules =
    (map (ifc: "iifname \"${ifc}\" udp dport 67 accept") dhcpIfaces)
    ++ lib.optionals dnsEnabled (
      map (ifc: "iifname \"${ifc}\" udp dport 53 accept") dnsIfaces
      ++ map (ifc: "iifname \"${ifc}\" tcp dport 53 accept") dnsIfaces
    )
    ++ map (ifc: "iifname \"${ifc}\" icmp type echo-request accept") lanIfaces
    ++ map (ifc: "iifname \"${ifc}\" icmpv6 type echo-request accept") lanIfaces;

  inputRules = lib.concatMap mkInputRules rules;
  forwardRules = lib.concatMap mkForwardRules rules;

  indent = lines: lib.concatMapStringsSep "\n" (l: "        ${l}") lines;
in
{
  config = lib.mkIf config.nixwall.enable {
    assertions = [
      {
        assertion = builtins.isList rules;
        message = "nixwall.firewall.rules must be a list.";
      }
      {
        assertion =
          !builtins.isList rules
          || lib.all (
            r:
            let
              f = r.from or null;
              t = r.to or null;
            in
            (f == null || lib.hasAttr f zoneToIface) && (t == null || isFW t || lib.hasAttr t zoneToIface)
          ) rules;
        message = "Every firewall rule must reference zones defined in nixwall interfaces.";
      }
      {
        assertion = lib.all (z: lib.hasAttr z zoneToIface) masqueradeZones;
        message = "nixwall.nat: every nat.masquerade zone must exist in nixwall interfaces.";
      }
    ];

    networking.nftables = {
      enable = true;
      ruleset = ''
        table inet filter {
          chain input {
            type filter hook input priority 0; policy drop;
            ct state established,related accept
            iifname "lo" accept
        ${indent implicitRules}
        ${indent inputRules}
          }

          chain forward {
            type filter hook forward priority 0; policy drop;
            ct state established,related accept
        ${indent forwardRules}
          }

          chain output {
            type filter hook output priority 0; policy accept;
          }
        }

        ${lib.optionalString (natRules != [ ]) ''
          table inet nat {
            chain postrouting {
              type nat hook postrouting priority 100;
          ${indent natRules}
            }
          }
        ''}
      '';
    };

    networking.firewall.enable = false;
  };
}
