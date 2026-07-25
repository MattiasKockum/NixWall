{ pkgs, ... }:
let
  lanMac = "52:54:00:00:0a:01";
in
pkgs.testers.runNixOSTest {
  name = "unit/interfaces";

  nodes.nixwall =
    { lib, ... }:
    {
      imports = [ ../../../modules/nixwall.nix ];

      virtualisation.qemu.networkingOptions = lib.mkForce [
        "-netdev user,id=nlan"
        "-device virtio-net-pci,netdev=nlan,mac=${lanMac}"
        "-netdev user,id=nwan"
        "-device virtio-net-pci,netdev=nwan"
      ];

      nixwall = {
        enable = true;
        config = {
          version = 1;
          hostname = "nixwall";
          zones = {
            LAN = {
              mac = lanMac;
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
      };
    };

  testScript = ''
    start_all()
    nixwall.wait_for_unit("multi-user.target")

    print(nixwall.succeed("ip -o link"))

    print(nixwall.succeed("ip a"))
    print(nixwall.succeed("ip l"))

    nixwall.succeed("ip link show lan")
    nixwall.succeed("ip link show lan | grep -qi ${lanMac}")
    nixwall.fail("ip link show eth0")

    nixwall.succeed("ip link show eth1")
    nixwall.fail("ip link show wan")

    nixwall.succeed("ip -o -4 addr show dev lan  | grep -q 10.10.10.1/24")
    nixwall.succeed("ip -o -4 addr show dev eth1 | grep -q 10.100.100.1/24")

    nixwall.fail("ip -o -4 addr show dev eth2 | grep -q inet")
    nixwall.succeed("ip link show eth2 | grep -q 'state DOWN'")

    nixwall.succeed("ip route | grep -q 'default via 10.100.100.254 dev eth1'")
  '';
}
