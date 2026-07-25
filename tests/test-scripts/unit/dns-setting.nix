{ pkgs, ... }:
let
  cfgs = import ../../configs { inherit pkgs; };
in
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
      config = cfgs.mk [ { zones.WAN.dns = [ "10.100.100.101" ]; } ];
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
