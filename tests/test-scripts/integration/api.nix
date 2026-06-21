{ pkgs, ... }:
let
  nixwallConfig = {
    version = 1;
    interfaces = {
      LAN = "eth0";
      WAN = "eth1";
    };
    usersDefaults.initialPassword = "changeme";
    users = {
      alice = {
        wheel = true;
      };
      bob = {
        groups = [ "developers" ];
      };
    };
    network = {
      hostname = "nixwall";
      addresses = {
        LAN = "10.10.10.1/24";
        WAN = "10.100.100.1/24";
      };
      gateway = "10.100.100.254";
      dns = [ "10.100.100.10" ];
    };
    dhcp.subnets.LAN = {
      cidr = "10.10.10.0/24";
      range = "10.10.10.50-10.10.10.150";
      leaseSeconds = 86400;
    };
    firewall.rules = [
      {
        name = "api";
        from = "LAN";
        to = "FW";
        proto = "tcp";
        ports = 8080;
        action = "accept";
      }
    ];
  };

  nixwallConfigJSON = builtins.toJSON nixwallConfig;
in
pkgs.testers.runNixOSTest {
  name = "integration/api";

  nodes = {
    nixwall = { ... }: {
      imports = [
        ../../vms/firewall.nix
        ../../../modules/nixwall.nix
      ];

      nixwall = {
        enable = true;
        appliance = {
          enable = true;
          tls.enable = true;
          tls.generateSelfSigned = true;
          auth.enable = true;
          api.enable = true;
          seedEtc.enable = false;
        };
        config = nixwallConfig;
      };

      environment.etc."nixos/config.json".text = nixwallConfigJSON;

      system.activationScripts.nixwallTestGitInit.text = ''
        set -euo pipefail
        if [ ! -d /etc/nixos/.git ]; then
          mkdir -p /etc/nixos
          GIT_AUTHOR_NAME='NixWall Test' \
          GIT_AUTHOR_EMAIL='test@nixwall.invalid' \
          GIT_COMMITTER_NAME='NixWall Test' \
          GIT_COMMITTER_EMAIL='test@nixwall.invalid' \
          ${pkgs.git}/bin/git -C /etc/nixos init -b main
          GIT_AUTHOR_NAME='NixWall Test' \
          GIT_AUTHOR_EMAIL='test@nixwall.invalid' \
          GIT_COMMITTER_NAME='NixWall Test' \
          GIT_COMMITTER_EMAIL='test@nixwall.invalid' \
          ${pkgs.git}/bin/git -C /etc/nixos commit --allow-empty -m 'initial'
        fi
      '';
    };

    client = { ... }: {
      imports = [ ../../vms/client.nix ];
      networking = {
        useNetworkd = true;
        networkmanager.enable = false;
        useDHCP = true;
      };
      environment.systemPackages = [ pkgs.jq ];
    };
  };

  testScript = ''
    start_all()
    nixwall.wait_for_unit("multi-user.target")
    nixwall.wait_for_unit("nixwall-tls.service")
    nixwall.wait_for_unit("nixwall-api.service")
    client.wait_for_unit("multi-user.target")
    client.wait_until_succeeds("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.*'")


    client.wait_until_succeeds("test \"$(curl -sk -o /dev/null -w '%{http_code}' https://10.10.10.1:8080/interfaces)\" = 401")

    client.succeed("test \"$(curl -sk -u alice:wrongpassword -o /dev/null -w '%{http_code}' https://10.10.10.1:8080/interfaces)\" = 401")
    client.succeed("test \"$(curl -sk -u bob:wrongpassword   -o /dev/null -w '%{http_code}' https://10.10.10.1:8080/interfaces)\" = 401")

    client.succeed("curl -sk -u alice:changeme https://10.10.10.1:8080/interfaces | grep eth0")
    client.succeed("curl -sk -u bob:changeme   https://10.10.10.1:8080/interfaces | grep eth0")


    client.succeed("curl -sk -u alice:changeme https://10.10.10.1:8080/interfaces | grep eth1")


    client.succeed("curl -sk -u alice:changeme https://10.10.10.1:8080/config > /tmp/config.json")

    client.succeed("jq -r '.network.hostname'  /tmp/config.json | grep -x nixwall")
    client.succeed("jq -r '.network.addresses.LAN' /tmp/config.json | grep '10.10.10.1/24'")
    client.succeed("jq -r '.interfaces.LAN'    /tmp/config.json | grep -x eth0")
    client.succeed("jq -r '.interfaces.WAN'    /tmp/config.json | grep -x eth1")


    client.succeed("sed -i 's/\"hostname\":\"[^\"]*\"/\"hostname\":\"nixwall2\"/' /tmp/config.json")
    client.succeed("curl -sSk -u alice:changeme -X PUT https://10.10.10.1:8080/config -H 'Content-Type: application/json' --data-binary @/tmp/config.json")

    client.succeed("curl -sk -u alice:changeme https://10.10.10.1:8080/config > /tmp/config2.json")
    client.succeed("jq -r '.network.hostname' /tmp/config2.json | grep -x nixwall2")

    client.succeed("jq -S . /tmp/config.json  > /tmp/a.json")
    client.succeed("jq -S . /tmp/config2.json > /tmp/b.json")
    client.succeed("cmp -s /tmp/a.json /tmp/b.json")


    client.succeed("curl -sSk -u alice:changeme -X POST https://10.10.10.1:8080/git/commit -H 'Content-Type: application/json' --data '{\"message\":\"api test commit\"}' > /tmp/commit.json")

    client.succeed("jq -e '.steps[1].rc == 0' /tmp/commit.json > /dev/null")

    nixwall.succeed("git -C /etc/nixos log -1 --pretty=%B | grep -x 'api test commit'")

    nixwall.succeed("git -C /etc/nixos show --stat HEAD | grep config.json")
  '';
}
