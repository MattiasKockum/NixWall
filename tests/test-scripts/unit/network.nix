{ pkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "unit/network";

  nodes.nixwall = { ... }: {
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
      };
    };
  };

  testScript = ''
    start_all()
    nixwall.wait_for_unit("multi-user.target")

    nixwall.succeed("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.1/24 .*'")
    nixwall.succeed("ip -o -4 addr show dev eth1 | grep -x '.* 10.100.100.1/24 .*'")

    nixwall.succeed("ip route | grep 'default via 10.100.100.254 dev eth1'")

    nixwall.succeed("hostname | grep -x nixwall")

    nixwall.succeed("resolvectl dns | grep 10.100.100.10")

    nixwall.succeed("ip -o -4 addr show dev eth0 | grep -v dynamic")
    nixwall.succeed("ip -o -4 addr show dev eth1 | grep -v dynamic")

    nixwall.succeed("sysctl net.ipv4.ip_forward | grep '= 1'")
    nixwall.succeed("sysctl net.ipv6.conf.all.forwarding | grep '= 1'")
  '';
}
