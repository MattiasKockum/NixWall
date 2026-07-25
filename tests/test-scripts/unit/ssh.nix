{ pkgs, ... }:
let
  cfgs = import ../../configs { inherit pkgs; };

  mkKey =
    name:
    pkgs.runCommand "ssh-key-${name}" { } ''
      mkdir -p $out
      ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" -f $out/key -C "${name}@nixwall-test"
    '';

  rootKey = mkKey "root";
  aliceKey = mkKey "alice-1";
  alice2Key = mkKey "alice-2";
  bobKey = mkKey "bob";
in
pkgs.testers.runNixOSTest {
  name = "unit/ssh";

  nodes = {
    nixwall = { ... }: {
      imports = [
        ../../vms/firewall.nix
        ../../../modules/nixwall.nix
      ];

      nixwall = {
        enable = true;
        config = cfgs.mk (
          with cfgs.layers;
          [
            demoUsers
            {
              users = {
                root.ssh.authorizedKeys = [ (builtins.readFile "${rootKey}/key.pub") ];
                alice = {
                  passwordlessSudo = true;
                  ssh.authorizedKeys = [
                    (builtins.readFile "${aliceKey}/key.pub")
                    (builtins.readFile "${alice2Key}/key.pub")
                  ];
                };
                bob.ssh.authorizedKeys = [ (builtins.readFile "${bobKey}/key.pub") ];
              };

              firewall.rules = [
                {
                  name = "ssh";
                  from = "LAN";
                  to = "FW";
                  proto = "tcp";
                  ports = 22;
                  action = "accept";
                }
              ];

              services.ssh = {
                enable = true;
                listenZones = [ "LAN" ];
                passwordAuth = false;
                permitRootLogin = "prohibit-password";
              };
            }
          ]
        );
      };
    };

    client = { ... }: {
      imports = [ ../../vms/client.nix ];

      networking = {
        useNetworkd = true;
        networkmanager.enable = false;
        useDHCP = false;
        interfaces.eth0.ipv4.addresses = [
          {
            address = "10.10.10.2";
            prefixLength = 24;
          }
        ];
        defaultGateway = {
          address = "10.10.10.1";
          interface = "eth0";
        };
      };

      environment.systemPackages = [ pkgs.openssh ];

      system.activationScripts.sshTestKeyPerms = {
        text = ''
          set -euo pipefail
          mkdir -p /run/ssh-test
          cp ${rootKey}/key /run/ssh-test/root
          cp ${aliceKey}/key /run/ssh-test/alice1
          cp ${alice2Key}/key /run/ssh-test/alice2
          cp ${bobKey}/key /run/ssh-test/bob
          chmod 600 /run/ssh-test/root \
                    /run/ssh-test/alice1 \
                    /run/ssh-test/alice2 \
                    /run/ssh-test/bob
        '';
        deps = [ ];
      };
    };
  };

  testScript = ''
    start_all()
    nixwall.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")

    ssh = "ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    print(nixwall.succeed("sshd -T | grep -i listen"))

    client.succeed(f"{ssh} -i /run/ssh-test/root root@10.10.10.1 'id -un' | grep -x root")

    client.succeed(f"{ssh} -i /run/ssh-test/alice1 alice@10.10.10.1 'id -un' | grep -x alice")

    client.succeed(f"{ssh} -i /run/ssh-test/alice2 alice@10.10.10.1 'id -un' | grep -x alice")

    client.succeed(f"{ssh} -i /run/ssh-test/bob bob@10.10.10.1 'id -un' | grep -x bob")

    client.fail(f"{ssh} -o PreferredAuthentications=password -o PubkeyAuthentication=no alice@10.10.10.1 true")
    client.fail(f"{ssh} -o PreferredAuthentications=password -o PubkeyAuthentication=no root@10.10.10.1 true")

    client.fail(f"{ssh} -i /run/ssh-test/alice1 bob@10.10.10.1 'id -un'")

    client.fail(f"{ssh} -i /run/ssh-test/bob alice@10.10.10.1 'id -un'")

    nixwall.succeed("sshd -T | grep -i 'listenaddress 10.10.10.1'")
    nixwall.fail("sshd -T | grep -i 'listenaddress 10.100.100.1'")

    client.succeed(f"{ssh} -i /run/ssh-test/alice1 alice@10.10.10.1 'sudo -n id -un' | grep -x root")

    client.fail(f"{ssh} -i /run/ssh-test/bob bob@10.10.10.1 'sudo -n id -un'")
  '';
}
