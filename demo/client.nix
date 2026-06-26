_: {
  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 2048;
      diskSize = 8192;
      cores = 2;
      qemu.networkingOptions = [
        "-netdev bridge,id=net0,br=virbr-tb"
        "-device virtio-net-pci,netdev=net0"
      ];
    };
  };

  networking.hostName = "demo-client";

  programs.firefox.enable = true;

  services = {
    desktopManager.gnome.enable = true;
    displayManager.gdm.enable = true;

    displayManager.autoLogin = {
      enable = true;
      user = "user";
    };
  };

  users.users.user = {
    isNormalUser = true;
    password = "";
  };

  system.stateVersion = "25.05";
}
