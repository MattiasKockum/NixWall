{pkgs, ...}:
pkgs.testers.runNixOSTest {
  name = "Test that the VM correctly offers DHCP";

  nodes = {
    nixwall = {...}: {
      imports = [
        ../virtual-machines/light-firewall-vm.nix
        ../../modules/nixwall-options.nix
        ../../modules/users.nix
        ../../modules/network.nix
        ../../modules/firewall-rules.nix
        ../../modules/dhcp.nix
        ../../modules/nat.nix
        ../../modules/ssh.nix
        ../../modules/dashboard.nix
      ];

      nixwall.config = {
        version = 1;

        interfaces = {
          LAN = "eth0";
          WAN = "eth1";
        };

        usersDefaults = {initialPassword = "changeme";};

        users = {
          alice = {wheel = true;};
          bob = {groups = ["developers"];};
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

        services = {
          ssh = {
            enable = true;
            listenZones = ["LAN"];
            passwordAuth = false;
            permitRootLogin = "prohibit-password";
            root = {
              authorizedKeys = [
                (builtins.readFile ../assets/ssh/root_1_25519.pub)
              ];
            };
            users = {
              alice = {
                sshAuthorizedKeys = [
                  (builtins.readFile ../assets/ssh/alice_1_25519.pub)
                  (builtins.readFile ../assets/ssh/alice_2_25519.pub)
                ];
                passwordlessSudo = true;
              };
              bob = {
                sshAuthorizedKeys = [
                  (builtins.readFile ../assets/ssh/bob_1_25519.pub)
                ];
              };
            };
          };

          dashboard = {
            enable = true;
            port = 80;
            listenZones = ["LAN"];
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
        ../modules/ssh.nix
      ];
    };
  };

  testScript = ''
    start_all()

    nixwall.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")
    server.wait_for_unit("multi-user.target")
    client.wait_until_succeeds("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.*'")

    # SUCCESS : SSH from LAN to FW
    client.wait_until_succeeds("nc -zw2 10.10.10.1 22")
    # SUCCESS : HTTP from LAN to FW
    client.wait_until_succeeds("nc -zw2 10.10.10.1 80")

    # SUCCESS : SSH from LAN to WAN
    client.wait_until_succeeds("nc -zw2 10.100.100.100 22")
    # SUCCESS : HTTP from LAN to WAN
    client.wait_until_succeeds("curl -v http://10.100.100.100:80 | grep 'hello from server'")

    # FAIL : HTTP from WAN to FW
    server.fail("nc -zw2 10.100.100.1 80")
    # FAIL : SSH from WAN to FW
    server.fail("nc -zw2 10.100.100.1 22")
    # FAIL : HTTP2 from LAN to FW
    client.fail("nc -zw2 10.100.100.1 443")
  '';
}
