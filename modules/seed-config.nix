{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.nixwall.seedEtc;

  root = ../.;

  src = lib.cleanSourceWith {
    src = root;
    filter = path: _type: let
      p = toString path;
      r = lib.removePrefix ((toString root) + "/") p;
    in
      !(
        lib.hasPrefix "result" r
        || lib.hasPrefix ".git/" r
        || lib.hasPrefix ".direnv/" r
      );
  };
  sentinel = "${cfg.target}/flake.nix";
in {
  options.nixwall.seedEtc = {
    enable = lib.mkEnableOption "Seed /etc/nixos once (mutable copy).";
    target = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
    };

    gitInit = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      authorName = lib.mkOption {
        type = lib.types.str;
        default = "NixWall";
      };
      authorEmail = lib.mkOption {
        type = lib.types.str;
        default = "noreply@nixwall.invalid";
      };
      initialCommitMessage = lib.mkOption {
        type = lib.types.str;
        default = "first NixWall commit";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nixwall-seed-etc = {
      description = "Seed ${cfg.target} from repo once, then git init";
      wantedBy = ["multi-user.target"];
      before = ["multi-user.target"];
      after = ["local-fs.target"];
      requires = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RequiresMountsFor = [cfg.target];
      };
      script = ''
        set -eu

        if [ ! -e '${sentinel}' ]; then
          echo "Seeding ${cfg.target} from ${src}"
          rm -rf '${cfg.target}'
          mkdir -p '${cfg.target}'
          cp -aT ${src} '${cfg.target}'

          if ${lib.boolToString cfg.gitInit.enable}; then
            echo "Initializing git repository in ${cfg.target}"
            ${pkgs.git}/bin/git -C '${cfg.target}' init -b main
            ${pkgs.git}/bin/git -C '${cfg.target}' \
              -c user.name='${cfg.gitInit.authorName}' \
              -c user.email='${cfg.gitInit.authorEmail}' \
              add -A
            ${pkgs.git}/bin/git -C '${cfg.target}' \
              -c user.name='${cfg.gitInit.authorName}' \
              -c user.email='${cfg.gitInit.authorEmail}' \
              commit -m '${cfg.gitInit.initialCommitMessage}'
          fi

          touch '${sentinel}'
        else
          echo "Already seeded (${sentinel} exists), skipping."
        fi
      '';
    };
  };
}
