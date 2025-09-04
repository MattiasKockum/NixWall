{pkgs, ...}:
pkgs.testers.runNixOSTest {
  name = "Test that the VM correctly handles SSH";

  nodes = {
    nixwall = {...}: {
      imports = [
        ../virtual-machines/light-firewall-vm.nix
        ../../modules/nixwall-options.nix
        ../../modules/firewall-rules.nix
        ../../modules/users.nix
        ../../modules/network.nix
        ../../modules/dhcp.nix
        ../../modules/ssh.nix
      ];
      nixwall.config = {
        version = 1;

        usersDefaults = {initialPassword = "changeme";};

        users = {
          alice = {wheel = true;};
          bob = {groups = ["developers"];};
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

      environment = {
        systemPackages = [pkgs.openssh];
        etc = {
          "ssh-test/root_1_25519" = {
            text = builtins.readFile ../assets/ssh/root_1_25519;
            mode = "0600";
          };
          "ssh-test/alice_1_25519" = {
            text = builtins.readFile ../assets/ssh/alice_1_25519;
            mode = "0600";
          };
          "ssh-test/alice_2_25519" = {
            text = builtins.readFile ../assets/ssh/alice_2_25519;
            mode = "0600";
          };
          "ssh-test/bob_1_25519" = {
            text = builtins.readFile ../assets/ssh/bob_1_25519;
            mode = "0600";
          };
        };
      };
    };
  };

  testScript = ''
    start_all()

    nixwall.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")

    client.wait_until_succeeds("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.*'")


    ssh_base='ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

    client.succeed(f"{ssh_base} -i /etc/ssh-test/root_1_25519 root@10.10.10.1 'id -un' | grep -x root")
    client.succeed(f"{ssh_base} -i /etc/ssh-test/alice_1_25519 alice@10.10.10.1 'id -un' | grep -x alice")
    client.succeed(f"{ssh_base} -i /etc/ssh-test/alice_2_25519 alice@10.10.10.1 'id -un' | grep -x alice")
    client.succeed(f"{ssh_base} -i /etc/ssh-test/bob_1_25519 bob@10.10.10.1 'id -un' | grep -x bob")

    client.fail(f"{ssh_base} -o PreferredAuthentications=password -o PubkeyAuthentication=no alice@10.10.10.1 true")
  '';
}
