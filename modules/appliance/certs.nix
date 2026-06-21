{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.nixwall.appliance.tls;
in
{
  options.nixwall.appliance.tls = {
    enable = lib.mkEnableOption "NixWall TLS";

    dir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nixwall/tls";
    };

    certFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.nixwall.appliance.tls.dir}/cert.pem";
    };

    keyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.nixwall.appliance.tls.dir}/key.pem";
    };

    generateSelfSigned = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Generate a self-signed cert/key on first boot if missing.";
    };

    subject = lib.mkOption {
      type = lib.types.str;
      default = "/CN=nixwall";
    };

    days = lib.mkOption {
      type = lib.types.int;
      default = 3650;
    };
  };

  config = lib.mkIf (config.nixwall.enable && config.nixwall.appliance.enable && cfg.enable) {
    systemd.tmpfiles.rules = [
      "d ${cfg.dir} 0700 root root - -"
    ];

    systemd.services.nixwall-tls = lib.mkIf cfg.generateSelfSigned {
      description = "Generate NixWall TLS certificate and key";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
      };

      path = with pkgs; [
        openssl
        coreutils
      ];
      script = ''
        set -euo pipefail
        cert="${cfg.certFile}"
        key="${cfg.keyFile}"

        mkdir -p "$(dirname "$cert")"
        chmod 700 "$(dirname "$cert")"

        if [ ! -s "$cert" ] || [ ! -s "$key" ]; then
          openssl req -x509 -newkey rsa:4096 -nodes \
            -keyout "$key" \
            -out    "$cert" \
            -days   ${toString cfg.days} \
            -subj   "${cfg.subject}"
          chmod 600 "$key" "$cert"
        fi
      '';
    };
  };
}
