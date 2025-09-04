{pkgs, ...}:
pkgs.testers.runNixOSTest {
  name = "Test that the VM correctly offers DHCP";

  nodes = {
    nixwall = {...}: {
      imports = [
        ../virtual-machines/light-firewall-vm.nix
        ../../modules/nixwall-options.nix
        ../../modules/network.nix
        ../../modules/firewall-rules.nix
        ../../modules/dhcp.nix
        ../../modules/nat.nix
        ../../modules/ssh.nix
        ../../modules/dns.nix
      ];

      environment.systemPackages = with pkgs; [dig];

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
          dns = ["10.100.100.101"];
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

        services = {
          dns = {
            enable = true;
            port = 53;
            dict = {"machine.lan" = "10.10.10.2";};
            listenZones = ["LAN"];
            cacheSize = 2000;
          };
        };
      };
    };

    client = {...}: {
      imports = [
        ../virtual-machines/client.nix
      ];

      environment.systemPackages = with pkgs; [dig];

      networking = {
        useNetworkd = true;
        networkmanager.enable = false;
        useDHCP = true;
      };
    };

    dns = {...}: {
      imports = [
        ../virtual-machines/dns.nix
        ../modules/dns.nix
      ];
    };
  };

  testScript = ''
    start_all()

    nixwall.wait_for_unit("multi-user.target")
    dns.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")

    client.wait_until_succeeds("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.*'")

    client.succeed("dig machine.lan")
    client.succeed("dig website.net")
  '';
}
