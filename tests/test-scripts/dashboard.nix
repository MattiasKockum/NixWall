{pkgs, ...}:
pkgs.testers.runNixOSTest {
  name = "Test that the dashboard is working";

  nodes.nixwall = {...}: {
    imports = [
      ../virtual-machines/light-firewall-vm.nix
      ../../modules/nixwall-options.nix
      ../../modules/firewall-rules.nix
      ../../modules/network.nix
      ../../modules/dhcp.nix
      ../../modules/dashboard.nix
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
      firewall = {
        policies = {
          input = "drop";
          forward = "drop";
          output = "accept";
        };
        rules = [
          {
            name = "ssh-from-lan";
            action = "accept";
            from = "LAN";
            to = "FW";
            proto = "tcp";
            ports = 22;
          }
          {
            name = "dashboard";
            action = "accept";
            from = "LAN";
            to = "FW";
            proto = "tcp";
            ports = 80;
          }
          {
            name = "lan-to-wan";
            action = "accept";
            from = "LAN";
            to = "WAN";
            proto = "any";
          }
        ];
      };
      services = {
        dashboard = {
          enable = true;
          port = 80;
          listenZones = ["LAN"];
        };
      };
    };
  };

  nodes.client = {...}: {
    imports = [../virtual-machines/client.nix];
    networking = {
      useNetworkd = true;
      networkmanager.enable = false;
      useDHCP = true;
    };
  };

  testScript = ''
    start_all()

    nixwall.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")

    client.wait_until_succeeds("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.*'")

    nixwall.wait_for_unit("dashboard.service")
    nixwall.wait_until_succeeds("ss -ltn '( sport = :80 )' | grep -F LISTEN")
    client.wait_until_succeeds("curl -sSf --max-time 5 http://10.10.10.1:80 | grep -F 'NixWall dashboard'")
  '';
}
