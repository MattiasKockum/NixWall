{ pkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "integration/nat";

  nodes = {
    nixwall = { ... }: {
      imports = [
        ../../vms/firewall.nix
        ../../../modules/nixwall.nix
      ];
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
            dns = [ "10.100.100.10" ];
          };
          dhcp.subnets.LAN = {
            cidr = "10.10.10.0/24";
            range = "10.10.10.50-10.10.10.150";
            leaseSeconds = 86400;
          };
          nat.masquerade = [ "LAN" ];
          firewall.rules = [
            {
              name = "lan-to-wan";
              from = "LAN";
              to = "WAN";
              proto = "any";
              action = "accept";
            }
          ];
        };
      };
    };

    client = { ... }: {
      imports = [ ../../vms/client.nix ];
      networking = {
        useNetworkd = true;
        networkmanager.enable = false;
        useDHCP = true;
      };
      environment.systemPackages = [ pkgs.netcat-gnu ];
    };

    server = { ... }: {
      imports = [
        ../../vms/server.nix
        ../../helpers/web-server.nix
      ];
      environment.systemPackages = [ pkgs.netcat-gnu ];
    };
  };

  testScript = ''
    start_all()
    nixwall.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")
    server.wait_for_unit("multi-user.target")

    client.wait_until_succeeds("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.*'")

    client.succeed("ping -c1 -W2 10.10.10.1")

    server.fail("ping -c1 -W2 10.100.100.1")

    client.wait_until_succeeds("curl -sf --max-time 5 http://10.100.100.100:80 | grep 'hello from server'")

    server.succeed("journalctl -u web | grep 10.100.100.1")
    server.fail("journalctl -u web | grep 10.10.10.")

    server.fail("nc -zw2 10.100.100.1 80")
    server.fail("nc -zw2 10.100.100.1 22")
    server.fail("nc -zw2 10.100.100.1 443")

    client.fail("nc -zw2 10.10.10.1 443")
    client.fail("nc -zw2 10.10.10.1 22")
    client.fail("nc -zw2 10.10.10.1 80")
  '';
}
