{lib, ...}: {
  # Minimal configuration
  system.stateVersion = "25.05";
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # VM Network config
  virtualisation = {
    qemu.networkingOptions = lib.mkForce [];
    interfaces = {
      eth0.vlan = 2;
    };
  };

  networking = {
    useNetworkd = true;
    useDHCP = false;
    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.100.100.101";
          prefixLength = 24;
        }
      ];
    };
  };
}
