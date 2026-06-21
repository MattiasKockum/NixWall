{ lib, config, ... }: {
  config = lib.mkIf (config.nixwall.enable && config.nixwall.appliance.enable) {
    programs.git = {
      enable = true;
      config = {
        user.name = "NixWall API";
        user.email = "api@nixwall.local";
        init.defaultBranch = "main";
      };
    };
  };
}
