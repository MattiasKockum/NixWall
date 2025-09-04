{pkgs, ...}:
pkgs.testers.runNixOSTest {
  name = "Test that the VM correctly offers DHCP";

  nodes = {
    nixwall = {...}: {
      imports = [
        ../virtual-machines/light-firewall-vm.nix
        ../../modules/nixwall-options.nix
        ../../modules/network.nix
        ../../modules/dhcp.nix
        ../../modules/nat.nix
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
        dhcp = {
          subnets = {
            LAN = {
              cidr = "10.10.10.0/24";
              range = "10.10.10.50-10.10.10.150";
              leaseSeconds = 86400;
            };
          };
        };
        nat = {
          masquerade = ["LAN"];
        };
      };
    };

    client = {...}: {
      imports = [
        ../virtual-machines/client.nix
      ];

      networking = {
        useNetworkd = true;
        networkmanager.enable = false;

        useDHCP = true;
      };
    };

    server = {...}: {
      imports = [
        ../virtual-machines/server.nix
        ../modules/web-server.nix
      ];
    };
  };

  testScript = ''
    start_all()

    nixwall.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")
    server.wait_for_unit("multi-user.target")

    client.wait_until_succeeds("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.*'")

    client.succeed("curl -v http://10.100.100.100:80 | grep 'hello from server'")

    server.succeed("journalctl -u web | grep 10.100.100.1")
  '';
}
