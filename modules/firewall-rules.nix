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
  fw = parsed.firewall or {};
  rules = fw.rules or [];
  policies = fw.policies or {};

  toPortList = p:
    if p == null
    then []
    else if builtins.isList p
    then
      map (x:
        if builtins.isInt x
        then x
        else lib.toInt x)
      p
    else if builtins.isInt p
    then [p]
    else [(lib.toInt p)];

  isFW = t: t == "FW" || t == "fw" || t == "Firewall" || t == "self";

  perIfaceAllow =
    lib.foldl'
    (
      acc: r: let
        fromZone = r.from or null;
        toZone = r.to or null;
        proto = lib.toLower (r.proto or "any");
        ports = toPortList (r.ports or []);
        ifc =
          if fromZone != null
          then (zoneToIface.${fromZone} or null)
          else null;
        prev = acc.${ifc} or {};
      in
        if isFW toZone && ifc != null && ports != []
        then
          acc
          // {
            ${ifc} =
              if proto == "tcp"
              then prev // {allowedTCPPorts = (prev.allowedTCPPorts or []) ++ ports;}
              else if proto == "udp"
              then prev // {allowedUDPPorts = (prev.allowedUDPPorts or []) ++ ports;}
              else
                prev
                // {
                  allowedTCPPorts = (prev.allowedTCPPorts or []) ++ ports;
                  allowedUDPPorts = (prev.allowedUDPPorts or []) ++ ports;
                };
          }
        else acc
    )
    {}
    rules;

  interfacesAllow =
    lib.mapAttrs (_ifc: v: {
      allowedTCPPorts = lib.unique (v.allowedTCPPorts or []);
      allowedUDPPorts = lib.unique (v.allowedUDPPorts or []);
    })
    perIfaceAllow;

  mkFwdRulesFor = r: let
    fromZone = r.from or null;
    toZone = r.to or null;
    proto = lib.toLower (r.proto or "any");
    ports = toPortList (r.ports or []);
    iif =
      if fromZone != null
      then (zoneToIface.${fromZone} or null)
      else null;
    oif =
      if (toZone != null && !isFW toZone)
      then (zoneToIface.${toZone} or null)
      else null;

    portListStr = lib.concatStringsSep ", " (map toString ports);

    tcpRule =
      if ports == []
      then "iifname \"${iif}\" oifname \"${oif}\" accept"
      else "tcp dport { ${portListStr} } iifname \"${iif}\" oifname \"${oif}\" accept";
    udpRule =
      if ports == []
      then "iifname \"${iif}\" oifname \"${oif}\" accept"
      else "udp dport { ${portListStr} } iifname \"${iif}\" oifname \"${oif}\" accept";
  in
    if iif == null || oif == null
    then []
    else if proto == "tcp"
    then [tcpRule]
    else if proto == "udp"
    then [udpRule]
    else [tcpRule udpRule];

  forwardRules =
    lib.concatMap mkFwdRulesFor
    (lib.filter (r: !(isFW (r.to or "FW"))) rules);

  policyWarnings = let
    wanted = {
      input = "drop";
      forward = "drop";
      output = "accept";
    };
  in
    lib.concatLists (lib.mapAttrsToList (
        k: v:
          lib.optional (v != (wanted.${k} or v))
          "nixwall.firewall.policies.${k}=${toString v} is ignored (module uses NixOS defaults: ${wanted.${k}})."
      )
      policies);
in {
  config = {
    assertions = [
      {
        assertion = builtins.isList rules;
        message = "nixwall.firewall.rules must be a list.";
      }
      {
        assertion =
          lib.all (
            r: let
              f = r.from or null;
              t = r.to or null;
            in
              (f == null || lib.hasAttr f zoneToIface)
              && (t == null || isFW t || lib.hasAttr t zoneToIface)
          )
          rules;
        message = "Every firewall rule must reference zones present in .interfaces (for `from` and non-FW `to`).";
      }
    ];

    warnings = policyWarnings;

    networking = {
      nftables.enable = true;
      firewall = {
        enable = true;
        filterForward = true;
        interfaces = interfacesAllow;
        extraForwardRules = lib.concatStringsSep "\n" forwardRules;
      };
    };
  };
}
