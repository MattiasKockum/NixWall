{ pkgs }:
let
  inherit (pkgs) lib;

  base = {
    version = 1;
    hostname = "nixwall";

    zones = {
      LAN = {
        name = "eth0";
        address = "10.10.10.1/24";
      };
      WAN = {
        name = "eth1";
        address = "10.100.100.1/24";
        gateway = "10.100.100.254";
        dns = [ "10.100.100.10" ];
      };
    };
  };

  dhcpLAN.zones.LAN.dhcp = {
    range = "10.10.10.50-10.10.10.150";
    leaseSeconds = 86400;
  };

  masqLAN.zones.LAN.masquerade = true;

  demoUsers.users = {
    alice = {
      wheel = true;
      initialPassword = "changeme";
      ssh.authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPzZm9OdiwdnERpkPbcL2cLo8BX0OL+JMdTHTeyfLV/G alice@test"
      ];
    };
    bob = {
      groups = [ "developers" ];
      ssh.authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBtzGrILUf6GhgSWrO9dCICmqprYRWXAbnpmiYFPvWVW bob@test"
      ];
    };
  };
in
rec {
  inherit base;

  layers = { inherit dhcpLAN masqLAN demoUsers; };

  mk = extraLayers: lib.foldl' lib.recursiveUpdate base extraLayers;

  scenarios = {
    minimal = mk [ ];
    minimal-dhcp = mk [ dhcpLAN ];

    api = mk [
      dhcpLAN
      demoUsers
      { users.bob.initialPassword = "changeme"; }
      {
        firewall.rules = [
          {
            name = "api";
            from = "LAN";
            to = "FW";
            proto = "tcp";
            ports = 8080;
            action = "accept";
          }
        ];
      }
    ];

    dns-server = mk [
      dhcpLAN
      {
        zones.WAN.dns = [ "10.100.100.101" ];
        services.dns = {
          enable = true;
          port = 53;
          dict."machine.lan" = "10.10.10.2";
          listenZones = [ "LAN" ];
          cacheSize = 2000;
        };
      }
    ];
  };

  files = lib.mapAttrs (name: cfg: (pkgs.formats.toml { }).generate "${name}.toml" cfg) scenarios;
}
