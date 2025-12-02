{pkgs, ...}:
pkgs.testers.runNixOSTest {
  name = "Test that the API is working";

  nodes = {
    nixwall = {...}: {
      imports = [
        ../virtual-machines/light-firewall-vm.nix
        ../../modules/nixwall-options.nix
        ../../modules/users.nix
        ../../modules/firewall-rules.nix
        ../../modules/network.nix
        ../../modules/dhcp.nix
        ../../modules/api.nix
        ../../modules/seed-config.nix
        ../../modules/certs.nix
        ../../modules/pam.nix
        ../../modules/git.nix
      ];

      nixwall = {
        seedEtc.enable = true;
        tls.enable = true;
        tls.generateSelfSigned = true;
        auth.enable = true;

        config = {
          version = 1;

          usersDefaults = {
            initialPassword = "changeme";
          };
          users = {
            alice = {
              wheel = true;
            };
            bob = {
              groups = ["developers"];
            };
          };

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

    # Unauthorized access (must be 401 over HTTPS)
    client.succeed("test \"$(curl -sk -o /dev/null -w '%{http_code}' https://10.10.10.1:8080/interfaces)\" = 401")
    client.succeed("test \"$(curl -sk -u alice:wrongpassword -o /dev/null -w '%{http_code}' https://10.10.10.1:8080/interfaces)\" = 401")
    client.succeed("test \"$(curl -sk -u bob:wrongpassword   -o /dev/null -w '%{http_code}' https://10.10.10.1:8080/interfaces)\" = 401")

    # Authorized access
    client.wait_until_succeeds("curl -sk -u alice:changeme https://10.10.10.1:8080/interfaces > interfaces.out")
    client.succeed("grep -q eth0 interfaces.out")
    client.succeed("grep -q eth1 interfaces.out")

    # list interfaces
    client.wait_until_succeeds("curl -sk -u alice:changeme https://10.10.10.1:8080/interfaces > interfaces.out")
    client.succeed("cat interfaces.out | grep eth0")
    client.succeed("cat interfaces.out | grep eth1")

    # Config pull and push
    client.succeed("curl -sk -u alice:changeme https://10.10.10.1:8080/config > /tmp/config.json")
    client.succeed("jq -r '.network.hostname' /tmp/config.json | grep -x nixwall")
    client.succeed("sed -i 's/\"hostname\":\"[^\"]*\"/\"hostname\":\"nixwall2\"/' /tmp/config.json")
    client.succeed("curl -sSk -u alice:changeme -X PUT https://10.10.10.1:8080/config -H 'Content-Type: application/json' --data-binary @/tmp/config.json")
    client.succeed("curl -sk -u alice:changeme https://10.10.10.1:8080/config > /tmp/config2.json")
    client.succeed("jq -S . /tmp/config.json  > /tmp/a.json")
    client.succeed("jq -S . /tmp/config2.json > /tmp/b.json")
    client.succeed("cmp -s /tmp/a.json /tmp/b.json")

    client.succeed("curl -sSk -u alice:changeme -X POST https://10.10.10.1:8080/git/commit -H 'Content-Type: application/json' --data '{\"message\":\"api test commit\"}' > /tmp/commit.json")
    client.succeed("jq -e '.steps[1].rc == 0' /tmp/commit.json > /dev/null")
    nixwall.succeed("git -C /etc/nixos log -1 --pretty=%B | grep -x 'api test commit'")
    print(nixwall.execute("git -C /etc/nixos log")[1])
  '';
}
