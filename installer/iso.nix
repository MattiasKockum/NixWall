{
  lib,
  pkgs,
  config,
  self,
  nixpkgs,
  ...
}: let
  targetSystem = nixpkgs.lib.nixosSystem {
    inherit (pkgs.stdenv.hostPlatform) system;
    modules = [
      (self + "/profiles/default.nix")
      ({lib, ...}: {
        fileSystems."/" = lib.mkDefault {
          device = "rootfs";
          fsType = "tmpfs";
        };
        boot = {
          loader.grub.enable = lib.mkForce false;
          loader.systemd-boot.enable = lib.mkForce false;
        };
      })
    ];
    specialArgs = {inherit self nixpkgs;};
  };

  ci = pkgs.closureInfo {
    rootPaths = [targetSystem.config.system.build.toplevel];
  };

  toPaths = ci: let
    raw = lib.splitString "\n" (builtins.readFile "${ci}/store-paths");
  in
    lib.unique (builtins.filter (p: p != "" && lib.hasPrefix "/" p) raw);

  installerPkg = pkgs.callPackage (self + "/installer/scripts") {};
in {
  fileSystems."/" = lib.mkDefault {
    device = "rootfs";
    fsType = "tmpfs";
  };
  boot = {
    loader.grub.enable = lib.mkForce false;
    loader.systemd-boot.enable = lib.mkForce false;
    supportedFilesystems = ["squashfs" "iso9660"];
  };

  system.extraDependencies = toPaths ci;

  isoImage.contents = [
    {
      source = self;
      target = "/nixwall";
    }
  ];
  image = {
    baseName = lib.mkForce "nixwall-installer-${config.system.nixos.release}-${config.system.nixos.version}-${pkgs.stdenv.hostPlatform.system}";
    extension = "iso";
  };

  environment.systemPackages = with pkgs; [
    installerPkg
    nix
    git
    parted
    e2fsprogs
    util-linux
    coreutils
    gawk
    gnugrep
    disko
    vim
  ];

  imports = [
    modules/greeter.nix
    modules/service-flake-copy.nix
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];
}
