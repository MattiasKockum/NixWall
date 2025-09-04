{
  lib,
  pkgs,
  ...
}: let
  ini = lib.generators.toINI {} {
    user.name = "API user";
    user.email = "api@nixwall.net";

    core.editor = "nvim";
    pull.rebase = "false";
    init.defaultBranch = "main";
    color.ui = "auto";
  };
in {
  environment.systemPackages = [
    pkgs.git
    pkgs.neovim
  ];

  environment.etc."gitconfig".text = ini;

  system.activationScripts.nixwallGitRootLink = {
    text = ''
      set -eu
      mkdir -p /root
      ln -sfn /etc/gitconfig /root/.gitconfig
    '';
  };
}
