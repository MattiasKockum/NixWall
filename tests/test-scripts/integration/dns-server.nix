{ pkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "integration/dns-server";

  nodes = {
    nixwall = { ... }: {
      imports = [
        ../../vms/firewall.nix
        ../../../modules/nixwall.nix
      ];

      environment.systemPackages = [ pkgs.dig ];

      nixwall = {
        enable = true;
        config = {
          version = 1;
          interfaces = {
            LAN = "eth0";
            WAN = "eth1";
          };
          network = {
            hostname = "nixwall";
            addresses = {
              LAN = "10.10.10.1/24";
              WAN = "10.100.100.1/24";
            };
            gateway = "10.100.100.254";
            dns = [ "10.100.100.101" ];
          };
          dhcp.subnets.LAN = {
            cidr = "10.10.10.0/24";
            range = "10.10.10.50-10.10.10.150";
            leaseSeconds = 86400;
          };
          services.dns = {
            enable = true;
            port = 53;
            dict = {
              "machine.lan" = "10.10.10.2";
            };
            listenZones = [ "LAN" ];
            cacheSize = 2000;
          };
        };
      };
    };

    client = { ... }: {
      imports = [ ../../vms/client.nix ];
      environment.systemPackages = [ pkgs.dig ];
      networking = {
        useNetworkd = true;
        networkmanager.enable = false;
        useDHCP = true;
      };
    };

    dns = { ... }: {
      imports = [
        ../../vms/dns.nix
        ../../helpers/dns.nix
      ];
    };
  };

  testScript = ''
    start_all()
    nixwall.wait_for_unit("multi-user.target")
    dns.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")

    client.wait_until_succeeds("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.*'")

    client.succeed("resolvectl dns eth0 | grep 10.10.10.1")

    client.succeed("dig +short machine.lan @10.10.10.1 | grep 10.10.10.2")
    client.succeed("dig +short website.net @10.10.10.1 | grep 10.100.100.100")

    client.succeed("dig +short machine.lan | grep 10.10.10.2")
    client.succeed("dig +short website.net | grep 10.100.100.100")
  '';

}
