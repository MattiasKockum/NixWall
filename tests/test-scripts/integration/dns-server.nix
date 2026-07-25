{ pkgs, ... }:
let
  cfgs = import ../../configs { inherit pkgs; };
in
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
        config = cfgs.scenarios.dns-server;
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
