{ lib, config, ... }:
let
  zones = config.nixwall.internal.zones or { };
  byMac = lib.filterAttrs (_: z: z ? mac) zones;
in
{
  config = lib.mkIf config.nixwall.enable {
    systemd.network.links = lib.mapAttrs' (
      zone: z:
      lib.nameValuePair "10-nixwall-${lib.toLower zone}" {
        matchConfig.MACAddress = z.mac;
        linkConfig.Name = lib.toLower zone;
      }
    ) byMac;
  };
}
