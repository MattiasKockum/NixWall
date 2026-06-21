{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.nixwall.appliance.seedEtc;
  root = ../..;
  src = lib.cleanSourceWith {
    src = root;
    filter =
      path: _type:
      let
        p = toString path;
        r = lib.removePrefix ((toString root) + "/") p;
      in
      !(
        lib.hasPrefix "result" r
        || lib.hasPrefix ".git" r
        || lib.hasPrefix ".direnv" r
        || lib.hasPrefix "tests" r
        || r == ".pre-commit-config.yaml"
      );
  };
  sentinel = "${cfg.target}/flake.nix";
in
{
  options.nixwall.appliance.seedEtc = {
    enable = lib.mkEnableOption "Seed /etc/nixos on first boot (mutable copy).";

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

  config = lib.mkIf (config.nixwall.enable && config.nixwall.appliance.enable && cfg.enable) {
    systemd.services.nixwall-seed-etc = {
      description = "Seed ${cfg.target} from store on first boot";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      requires = [ "local-fs.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RequiresMountsFor = [ cfg.target ];
      };

      script = ''
        set -euo pipefail

        if [ -e '${sentinel}' ]; then
          echo "Already seeded (${sentinel} exists), skipping."
          exit 0
        fi

        echo "Seeding ${cfg.target} from Nix store..."
        rm -rf '${cfg.target}'
        mkdir -p '${cfg.target}'
        cp -aT --no-preserve=mode ${src} '${cfg.target}'
        chmod -R u+w '${cfg.target}'

        ${lib.optionalString cfg.gitInit.enable ''
          echo "Initializing git repository..."
          ${pkgs.git}/bin/git -C '${cfg.target}' init -b main
          ${pkgs.git}/bin/git -C '${cfg.target}' add -A
          GIT_AUTHOR_NAME='${cfg.gitInit.authorName}' \
          GIT_AUTHOR_EMAIL='${cfg.gitInit.authorEmail}' \
          GIT_COMMITTER_NAME='${cfg.gitInit.authorName}' \
          GIT_COMMITTER_EMAIL='${cfg.gitInit.authorEmail}' \
          ${pkgs.git}/bin/git -C '${cfg.target}' \
            commit -m '${cfg.gitInit.initialCommitMessage}'
        ''}

      '';
    };
  };
}
