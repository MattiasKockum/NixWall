{pkgs, ...}:
pkgs.testers.runNixOSTest {
  name = "Test that the API is working";

  nodes = {
    nixwall = {...}: {
      imports = [
        ../virtual-machines/light-firewall-vm.nix
        ../../modules/nixwall-options.nix
        ../../modules/firewall-rules.nix
        ../../modules/network.nix
        ../../modules/dhcp.nix
        ../../modules/api.nix
        ../../modules/seed-config.nix
        ../../modules/git.nix
      ];

      nixwall.seedEtc.enable = true;

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
              name = "api";
              action = "accept";
              from = "LAN";
              to = "FW";
              proto = "tcp";
              ports = 8080;
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
          api = {
            enable = true;
            listenZones = ["LAN"];
            port = 8080;
          };
        };
      };
    };

    client = {...}: {
      imports = [../virtual-machines/client.nix];
      networking = {
        useNetworkd = true;
        networkmanager.enable = false;
        useDHCP = true;
      };
      environment.systemPackages = [pkgs.jq];
    };
  };

  testScript = ''
    start_all()

    nixwall.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")
    client.wait_until_succeeds("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.*'")

    # list interfaces
    client.wait_until_succeeds("curl -s http://10.10.10.1:8080/interfaces > interfaces.out")
    client.succeed("cat interfaces.out | grep eth0")
    client.succeed("cat interfaces.out | grep eth1")

    # Config pull and push
    client.succeed("curl -s http://10.10.10.1:8080/config > /tmp/config.json")
    client.succeed("jq -r '.network.hostname' /tmp/config.json | grep -x nixwall")
    client.succeed("sed -i 's/\"hostname\":\"[^\"]*\"/\"hostname\":\"nixwall2\"/' /tmp/config.json")
    client.succeed("curl -sS -X PUT http://10.10.10.1:8080/config -H 'Content-Type: application/json' --data-binary @/tmp/config.json")
    client.succeed("curl -s http://10.10.10.1:8080/config > /tmp/config2.json")
    client.succeed("jq -S . /tmp/config.json  > /tmp/a.json")
    client.succeed("jq -S . /tmp/config2.json > /tmp/b.json")
    client.succeed("cmp -s /tmp/a.json /tmp/b.json")

    client.succeed("curl -sS -X POST http://10.10.10.1:8080/git/commit -H 'Content-Type: application/json' --data '{\"message\":\"api test commit\"}' > /tmp/commit.json")
    client.succeed("jq -e '.steps[1].rc == 0' /tmp/commit.json > /dev/null")
    nixwall.succeed("git -C /etc/nixos log -1 --pretty=%B | grep -x 'api test commit'")
    print(nixwall.execute("git -C /etc/nixos log")[1])
  '';
}
