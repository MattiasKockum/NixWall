_: {
  virtualisation = {
    cores = 8;
    memorySize = 32768;
    diskSize = 60 * 1024;
  };

  swapDevices = [
    {
      device = "/swapfile";
      size = 16384;
    }
  ];

  nix.settings = {
    max-jobs = 2;
    cores = 4;
  };

  boot.tmp = {
    useTmpfs = true;
    tmpfsSize = "4G";
  };

  services.journald = {
    storage = "volatile";
    extraConfig = ''
      SystemMaxUse=128M
      RuntimeMaxUse=128M
    '';
  };
}
