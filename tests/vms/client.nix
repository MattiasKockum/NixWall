{ lib, ... }: {
  system.stateVersion = "25.05";
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  virtualisation.qemu.networkingOptions = lib.mkForce [ ];
  virtualisation.interfaces = {
    eth0.vlan = 1;
  };
}
