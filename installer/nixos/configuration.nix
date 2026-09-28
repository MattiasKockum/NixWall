_:

{
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
    configFile = ./config.toml;
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.settings.flake-registry = "";

  system.stateVersion = "25.05";
}
