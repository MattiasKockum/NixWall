{pkgs, ...}:
pkgs.testers.runNixOSTest {
  name = "Test that the VM correctly sets up its IP addresses";

  nodes.nixwall = {...}: {
    imports = [
      ../virtual-machines/light-firewall-vm.nix
      ../../modules/nixwall-options.nix
      ../../modules/network.nix
    ];
    nixwall.config = {
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
        dns = ["10.100.100.10"];
      };
    };
  };

  testScript = ''
    start_all()

    nixwall.wait_for_unit("multi-user.target")

    nixwall.succeed("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.1/24 .*'")
    nixwall.succeed("ip -o -4 addr show dev eth1 | grep -x '.* 10.100.100.1/24 .*'")
    nixwall.succeed("ip route | grep -x '.*default via 10.100.100.254 dev eth1 proto static.*'")
  '';
}
