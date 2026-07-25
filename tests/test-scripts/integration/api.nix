{ pkgs, ... }:
let
  cfgs = import ../../configs { inherit pkgs; };

  configWithComments = pkgs.runCommand "config.toml" { } ''
    {
      echo "# NixWall configuration."
      echo "# Managed in git. The API edits it in place: comments must survive."
      echo ""
      echo "# zones.LAN.dhcp.leaseSeconds = 86400   # uncomment to change the DHCP lease"
      echo ""
      cat ${cfgs.files.api}
      echo ""
    } > $out
  '';
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
        config = cfgs.scenarios.api;
      };

      system.activationScripts.nixwallTestGitInit.text = ''
        set -euo pipefail

        mkdir -p /etc/nixos
        if [ ! -e /etc/nixos/config.toml ]; then
          cp ${configWithComments} /etc/nixos/config.toml
          chmod 644 /etc/nixos/config.toml
        fi

        if [ ! -d /etc/nixos/.git ]; then
          export GIT_AUTHOR_NAME='NixWall Test'
          export GIT_AUTHOR_EMAIL='test@nixwall.invalid'
          export GIT_COMMITTER_NAME='NixWall Test'
          export GIT_COMMITTER_EMAIL='test@nixwall.invalid'
          ${pkgs.git}/bin/git -C /etc/nixos init -b main
          ${pkgs.git}/bin/git -C /etc/nixos add -A
          ${pkgs.git}/bin/git -C /etc/nixos commit -m 'initial'
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

    client.succeed("jq -r '.hostname'          /tmp/config.json | grep -x nixwall")
    client.succeed("jq -r '.zones.LAN.address' /tmp/config.json | grep '10.10.10.1/24'")
    client.succeed("jq -r '.zones.LAN.name'    /tmp/config.json | grep -x eth0")
    client.succeed("jq -r '.zones.WAN.name'    /tmp/config.json | grep -x eth1")
    client.succeed("jq -r '.firewall.rules[0].ports' /tmp/config.json | grep -x 8080")


    nixwall.succeed("grep -q '^# NixWall configuration.' /etc/nixos/config.toml")
    nixwall.succeed("grep -q '^# zones.LAN.dhcp.leaseSeconds = 86400' /etc/nixos/config.toml")


    client.succeed("jq '.hostname = \"nixwall2\"' /tmp/config.json > /tmp/put.json")
    client.succeed("curl -sSk -u alice:changeme -X PUT https://10.10.10.1:8080/config -H 'Content-Type: application/json' --data-binary @/tmp/put.json")

    client.succeed("curl -sk -u alice:changeme https://10.10.10.1:8080/config > /tmp/config2.json")
    client.succeed("jq -r '.hostname' /tmp/config2.json | grep -x nixwall2")


    client.succeed("jq -S . /tmp/put.json     > /tmp/a.json")
    client.succeed("jq -S . /tmp/config2.json > /tmp/b.json")
    client.succeed("cmp -s /tmp/a.json /tmp/b.json")


    nixwall.succeed("grep -q '^# NixWall configuration.' /etc/nixos/config.toml")
    nixwall.succeed("grep -q '^# zones.LAN.dhcp.leaseSeconds = 86400' /etc/nixos/config.toml")

    print(nixwall.succeed("git -C /etc/nixos diff --stat"))
    nixwall.succeed("git -C /etc/nixos diff --stat | grep -E '1 file changed.*1 insertion.*1 deletion'")


    client.succeed("curl -sSk -u alice:changeme -X POST https://10.10.10.1:8080/git/commit -H 'Content-Type: application/json' --data '{\"message\":\"api test commit\"}' > /tmp/commit.json")

    client.succeed("jq -e '.steps[1].rc == 0' /tmp/commit.json > /dev/null")

    nixwall.succeed("git -C /etc/nixos log -1 --pretty=%B | grep -x 'api test commit'")

    nixwall.succeed("git -C /etc/nixos show --stat HEAD | grep config.toml")
  '';
}
