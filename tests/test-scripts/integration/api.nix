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
        configFile = configWithComments;
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
    import json

    start_all()
    nixwall.wait_for_unit("multi-user.target")
    nixwall.wait_for_unit("nixwall-tls.service")
    nixwall.wait_for_unit("nixwall-api.service")
    client.wait_for_unit("multi-user.target")
    client.wait_until_succeeds("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.*'")

    client.wait_until_succeeds(
        "test \"$(curl -sk -o /dev/null -w '%{http_code}' https://10.10.10.1:8080/interfaces)\" = 401"
    )

    client.succeed(
        "test \"$(curl -sk -u alice:changeme -o /dev/null -w '%{http_code}' "
        + "https://10.10.10.1:8080/interfaces)\" = 401"
    )

    client.succeed(
        "test \"$(curl -sk -u alice:wrongpassword -X POST -o /dev/null -w '%{http_code}' "
        + "https://10.10.10.1:8080/auth/ticket)\" = 401"
    )

    alice_ticket = json.loads(
        client.succeed("curl -sSk -u alice:changeme -X POST https://10.10.10.1:8080/auth/ticket")
    )
    bob_ticket = json.loads(
        client.succeed("curl -sSk -u bob:changeme -X POST https://10.10.10.1:8080/auth/ticket")
    )
    assert "ticket" in alice_ticket and "CSRFPreventionToken" in alice_ticket
    assert alice_ticket != bob_ticket

    alice_auth_hdr = "-H 'Authorization: Bearer " + alice_ticket["ticket"] + "'"
    alice_csrf_hdr = "-H 'CSRFPreventionToken: " + alice_ticket["CSRFPreventionToken"] + "'"
    bob_auth_hdr = "-H 'Authorization: Bearer " + bob_ticket["ticket"] + "'"
    bob_csrf_hdr = "-H 'CSRFPreventionToken: " + bob_ticket["CSRFPreventionToken"] + "'"

    client.succeed("curl -sk " + alice_auth_hdr + " https://10.10.10.1:8080/interfaces | grep eth0")
    client.succeed("curl -sk " + bob_auth_hdr + " https://10.10.10.1:8080/interfaces | grep eth0")
    client.succeed("curl -sk " + alice_auth_hdr + " https://10.10.10.1:8080/interfaces | grep eth1")

    code = client.succeed(
        "curl -sk "
        + alice_auth_hdr
        + " -X PUT -o /dev/null -w '%{http_code}' https://10.10.10.1:8080/config "
        + "-H 'Content-Type: application/json' --data '{}'"
    ).strip()
    assert code == "403", f"expected 403 without CSRF header, got {code}"

    client.succeed(
        "curl -sk " + alice_auth_hdr + " https://10.10.10.1:8080/config > /tmp/config.json"
    )

    client.succeed("jq -r '.hostname' /tmp/config.json | grep -x nixwall")
    client.succeed("jq -r '.zones.LAN.address' /tmp/config.json | grep '10.10.10.1/24'")
    client.succeed("jq -r '.zones.LAN.name' /tmp/config.json | grep -x eth0")
    client.succeed("jq -r '.zones.WAN.name' /tmp/config.json | grep -x eth1")
    client.succeed("jq -r '.firewall.rules[0].ports' /tmp/config.json | grep -x 8080")

    nixwall.succeed("grep -q '^# NixWall configuration.' /etc/nixos/config.toml")
    nixwall.succeed("grep -q '^# zones.LAN.dhcp.leaseSeconds = 86400' /etc/nixos/config.toml")

    client.succeed("jq '.hostname = \"nixwall2\"' /tmp/config.json > /tmp/put.json")
    put_status = client.succeed(
        "curl -sSk -o /tmp/put_resp.json -w '%{http_code}' "
        + alice_auth_hdr
        + " "
        + alice_csrf_hdr
        + " -X PUT https://10.10.10.1:8080/config "
        + "-H 'Content-Type: application/json' --data-binary @/tmp/put.json"
    ).strip()
    assert put_status == "200", f"expected 200 from the authenticated PUT, got {put_status}"

    client.succeed(
        "curl -sk " + alice_auth_hdr + " https://10.10.10.1:8080/config > /tmp/config2.json"
    )
    client.succeed("jq -r '.hostname' /tmp/config2.json | grep -x nixwall2")

    client.succeed("jq -S . /tmp/put.json > /tmp/a.json")
    client.succeed("jq -S . /tmp/config2.json > /tmp/b.json")
    client.succeed("cmp -s /tmp/a.json /tmp/b.json")

    nixwall.succeed("grep -q '^# NixWall configuration.' /etc/nixos/config.toml")
    nixwall.succeed("grep -q '^# zones.LAN.dhcp.leaseSeconds = 86400' /etc/nixos/config.toml")

    nixwall.succeed("git -C /etc/nixos diff --stat | grep -E '1 file changed.*1 insertion.*1 deletion'")

    client.succeed(
        "curl -sSk "
        + alice_auth_hdr
        + " "
        + alice_csrf_hdr
        + " -X POST https://10.10.10.1:8080/git/commit "
        + "-H 'Content-Type: application/json' --data '{\"message\":\"api test commit\"}' "
        + "> /tmp/commit.json"
    )
    client.succeed("jq -e '.steps[1].rc == 0' /tmp/commit.json > /dev/null")

    nixwall.succeed("git -C /etc/nixos log -1 --pretty=%B | grep -x 'api test commit'")
    nixwall.succeed("git -C /etc/nixos show --stat HEAD | grep config.toml")

    token_resp = json.loads(
        client.succeed(
            "curl -sSk -u alice:changeme -X POST https://10.10.10.1:8080/auth/token "
            + "-H 'Content-Type: application/json' --data '{\"comment\":\"ci token\"}'"
        )
    )
    assert "full_token" in token_resp
    token_auth_hdr = "-H 'Authorization: Bearer " + token_resp["full_token"] + "'"

    client.succeed("curl -sk " + token_auth_hdr + " https://10.10.10.1:8080/interfaces | grep eth0")

    client.succeed(
        "curl -sSk "
        + token_auth_hdr
        + " -X PUT https://10.10.10.1:8080/config "
        + "-H 'Content-Type: application/json' --data-binary @/tmp/put.json"
    )

    tokens_list = json.loads(
        client.succeed("curl -sk " + token_auth_hdr + " https://10.10.10.1:8080/auth/token")
    )
    assert any(t["tokenid"] == token_resp["tokenid"] for t in tokens_list)

    code = client.succeed(
        "curl -sk "
        + bob_auth_hdr
        + " "
        + bob_csrf_hdr
        + " -X DELETE -o /dev/null -w '%{http_code}' "
        + "https://10.10.10.1:8080/auth/token/"
        + token_resp["tokenid"]
    ).strip()
    assert code == "404", f"expected 404 for another user's token, got {code}"

    client.succeed(
        "curl -sSk " + token_auth_hdr + " -X DELETE https://10.10.10.1:8080/auth/token/" + token_resp["tokenid"]
    )
    code = client.succeed(
        "curl -sk "
        + token_auth_hdr
        + " -o /dev/null -w '%{http_code}' https://10.10.10.1:8080/interfaces"
    ).strip()
    assert code == "401", f"expected 401 for a revoked token, got {code}"
  '';
}
