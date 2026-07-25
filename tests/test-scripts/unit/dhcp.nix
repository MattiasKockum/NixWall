{ pkgs, ... }:
let
  cfgs = import ../../configs { inherit pkgs; };
in
pkgs.testers.runNixOSTest {
  name = "unit/dhcp";

  nodes = {
    nixwall = { ... }: {
      imports = [
        ../../vms/firewall.nix
        ../../../modules/nixwall.nix
      ];
      nixwall = {
        enable = true;
        config = cfgs.scenarios.minimal-dhcp;
      };
    };

    client = { ... }: {
      imports = [ ../../vms/client.nix ];
      networking = {
        useNetworkd = true;
        networkmanager.enable = false;
        useDHCP = true;
      };
    };
  };

  testScript = ''
    start_all()
    nixwall.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")

    client.wait_until_succeeds("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.*'")

    client.succeed("ip -o -4 addr show dev eth0 | grep -oP '10\\.10\\.10\\.\\K\\d+' | awk '$1 >= 50 && $1 <= 150'")

    client.succeed("ip route show default | grep '10.10.10.1'")

    nixwall.succeed("ss -ulnp | grep ':67'")

    nixwall.succeed("test -s /var/lib/dnsmasq/dnsmasq.leases")
  '';
}
