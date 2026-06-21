{ pkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "unit/dns-setting";

  nodes.nixwall = { ... }: {
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
      };
    };
  };

  nodes.dns = { ... }: {
    imports = [
      ../../vms/dns.nix
      ../../helpers/dns.nix
    ];
  };

  testScript = ''
    start_all()
    nixwall.wait_for_unit("multi-user.target")
    dns.wait_for_unit("multi-user.target")

    nixwall.succeed("resolvectl dns | grep 10.100.100.101")

    nixwall.succeed("dig +short website.net @10.100.100.101 | grep 10.100.100.100")

    nixwall.succeed("dig +short website.net | grep 10.100.100.100")
  '';
}
