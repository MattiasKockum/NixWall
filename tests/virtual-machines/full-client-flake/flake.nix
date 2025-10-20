{
  description = "Test VM (full client desktop)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux";
  in {
    nixosConfigurations.gnomeVm = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ({
          config,
          pkgs,
          lib,
          modulesPath,
          ...
        }: {
          networking = {
            hostName = "gnome-vm";
            useDHCP = lib.mkDefault true;
            networkmanager.enable = true;
          };

          time.timeZone = "Europe/Paris";
          i18n.defaultLocale = "fr_FR.UTF-8";
          console = {
            keyMap = "fr";
          };

          imports = [(modulesPath + "/profiles/qemu-guest.nix")];

          services.xserver = {
            enable = true;
            displayManager.gdm.enable = true;
            desktopManager.gnome.enable = true;
          };

          #sound.enable = true;
          #hardware.pulseaudio.enable = false;
          #services.pipewire = {
          #  enable = true;
          #  alsa.enable = true;
          #  alsa.support32Bit = true;
          #  pulse.enable = true;
          #};

          users.users.default = {
            isNormalUser = true;
            extraGroups = ["wheel" "networkmanager"];
            initialPassword = "test";
          };

          security.sudo.wheelNeedsPassword = false;

          environment.systemPackages = with pkgs; [
            firefox
            gnome-tweaks
          ];

          services.openssh.enable = true;

          boot.loader.grub.device = "/dev/vda";
          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };

          system.build.qcow2 = import (modulesPath + "/../lib/make-disk-image.nix") {
            inherit lib config pkgs;
            diskSize = 10 * 1024; # MiB
            format = "qcow2";
            partitionTableType = "hybrid";
            label = "nixos";
          };

          virtualisation.vmVariant = {
            virtualisation = {
              memorySize = 4096;
              cores = 2;
            };
          };
        })
      ];
    };
  };
}
