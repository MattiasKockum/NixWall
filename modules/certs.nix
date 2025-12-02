{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.nixwall.tls;

  certPath = cfg.certFile;
  keyPath = cfg.keyFile;
  dirPath = cfg.dir;
in {
  options.nixwall.tls = {
    enable = lib.mkEnableOption "NixWall TLS material";

    dir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nixwall/tls";
      description = "Runtime directory for TLS assets.";
    };

    certFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.nixwall.tls.dir}/cert.pem";
      description = "TLS certificate path (PEM).";
    };

    keyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.nixwall.tls.dir}/key.pem";
      description = "TLS private key path (PEM).";
    };

    generateSelfSigned = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Generate a self-signed cert/key if missing.";
    };

    subject = lib.mkOption {
      type = lib.types.str;
      default = "/CN=nixwall";
      description = "OpenSSL subject for the generated self-signed certificate.";
    };

    days = lib.mkOption {
      type = lib.types.int;
      default = 3650;
      description = "Validity period (days) for the generated self-signed certificate.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.generateSelfSigned -> (certPath != null && keyPath != null);
        message = "nixwall.tls.certFile and nixwall.tls.keyFile must be set when generateSelfSigned = true.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${dirPath} 0700 root root - -"
    ];

    systemd.services.nixwall-tls = lib.mkIf cfg.generateSelfSigned {
      description = "Generate NixWall TLS certificate and key (shared)";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
      };

      path = [pkgs.openssl pkgs.coreutils];

      script = ''
        set -euo pipefail

        cert="${certPath}"
        key="${keyPath}"

        mkdir -p "$(dirname "$cert")"
        chmod 700 "$(dirname "$cert")"

        if [ ! -s "$cert" ] || [ ! -s "$key" ]; then
          openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout "$key" \
            -out "$cert" \
            -days ${toString cfg.days} \
            -subj "${cfg.subject}"
          chmod 600 "$key" "$cert"
        fi
      '';
    };
  };
}
