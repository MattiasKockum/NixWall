{pkgs, ...}:
pkgs.testers.runNixOSTest {
  name = "nixwall: generates shared TLS certs";

  nodes = {
    nixwall = {...}: {
      imports = [
        ../virtual-machines/light-firewall-vm.nix
        ../../modules/nixwall-options.nix
        ../../modules/certs.nix
      ];

      nixwall.tls.enable = true;
      nixwall.tls.generateSelfSigned = true;
    };
  };

  testScript = ''
    start_all()
    nixwall.wait_for_unit("multi-user.target")

    # Ensure the generator ran
    nixwall.wait_for_unit("nixwall-tls.service")

    # Ensure cert/key were created and are non-empty
    nixwall.succeed("test -s /var/lib/nixwall/tls/cert.pem")
    nixwall.succeed("test -s /var/lib/nixwall/tls/key.pem")

    # Sanity checks
    nixwall.succeed("${pkgs.openssl}/bin/openssl x509 -in /var/lib/nixwall/tls/cert.pem -noout -subject")
    nixwall.succeed("${pkgs.openssl}/bin/openssl pkey -in /var/lib/nixwall/tls/key.pem -noout")
  '';
}
