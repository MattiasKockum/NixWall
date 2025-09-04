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
  natCfg = parsed.nat or {};
  masqueradeZones = natCfg.masquerade or [];
  wanIface = zoneToIface.WAN or null;

  zonesToIfaces = zones:
    lib.flatten (map
      (z: let i = zoneToIface.${z} or null; in lib.optional (i != null) i)
      zones);

  internalIfaces = zonesToIfaces masqueradeZones;
in {
  config = lib.mkIf (masqueradeZones != [] && wanIface != null) {
    assertions = [
      {
        assertion = lib.all (z: lib.hasAttr z zoneToIface) masqueradeZones;
        message = "nixwall.nat: every nat.masquerade <ZONE> must exist in interfaces mapping.";
      }
    ];

    networking.nat = {
      enable = true;
      externalInterface = wanIface;
      internalInterfaces = internalIfaces;
      enableIPv6 = false;
    };

    # networking.firewall.checkReversePath = "loose";
  };
}
