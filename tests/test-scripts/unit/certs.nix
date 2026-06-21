{ pkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "unit/certs";

  nodes.nixwall = { ... }: {
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
      };
      config = {
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
          dns = [ "10.100.100.10" ];
        };
      };
    };
  };

  testScript = ''
    start_all()
    nixwall.wait_for_unit("multi-user.target")
    nixwall.wait_for_unit("nixwall-tls.service")

    # Files exist and are non-empty
    nixwall.succeed("test -s /var/lib/nixwall/tls/cert.pem")
    nixwall.succeed("test -s /var/lib/nixwall/tls/key.pem")

    # Files are valid crypto material
    nixwall.succeed("${pkgs.openssl}/bin/openssl x509 -in /var/lib/nixwall/tls/cert.pem -noout -subject")
    nixwall.succeed("${pkgs.openssl}/bin/openssl pkey -in /var/lib/nixwall/tls/key.pem -noout")

    # Cert and key match (same public key)
    nixwall.succeed("${pkgs.openssl}/bin/openssl x509 -in /var/lib/nixwall/tls/cert.pem -noout -pubkey > /tmp/cert.pub")
    nixwall.succeed("${pkgs.openssl}/bin/openssl pkey -in /var/lib/nixwall/tls/key.pem -pubout > /tmp/key.pub")
    nixwall.succeed("diff /tmp/cert.pub /tmp/key.pub")

    # Permissions are restrictive (600)
    nixwall.succeed("stat -c '%a' /var/lib/nixwall/tls/cert.pem | grep -x 600")
    nixwall.succeed("stat -c '%a' /var/lib/nixwall/tls/key.pem  | grep -x 600")

    # Idempotency: restarting the service does not regenerate certs
    nixwall.succeed("md5sum /var/lib/nixwall/tls/cert.pem > /tmp/before.md5")
    nixwall.execute("systemctl restart nixwall-tls.service")
    nixwall.wait_for_unit("nixwall-tls.service")
    nixwall.succeed("md5sum /var/lib/nixwall/tls/cert.pem > /tmp/after.md5")
    nixwall.succeed("diff /tmp/before.md5 /tmp/after.md5")
  '';
}
