{
  self,
  modulesPath,
  lib,
  pkgs,
  config,
  ...
}:
let
  installerPkg = pkgs.callPackage ./scripts { };
  installerFlake = import ./installer-flake.nix { inherit pkgs lib self; };
  applianceBuild = self.nixosConfigurations.appliance-default.config.system.build;
in
{

  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    modules/greeter.nix
    modules/service-flake-copy.nix
  ];

  isoImage.contents = [
    {
      source = installerFlake;
      target = "/nixwall";
    }
  ];

  isoImage.storeContents = [
    self.packages.x86_64-linux.nixwall-api
    applianceBuild.toplevel
    applianceBuild.diskoScript
    pkgs.shellcheck-minimal
    self
    self.inputs.nixpkgs
    self.inputs.disko
    self.inputs.crane
    self.inputs.pre-commit-hooks
    self.inputs.pre-commit-hooks.inputs.flake-compat
    applianceBuild.diskoScript.inputDerivation
    applianceBuild.toplevel.inputDerivation
    pkgs.makeBinaryWrapper
  ]
  ++ (with pkgs; [
    cryptsetup # LUKS
    lvm2
    mdadm
    btrfs-progs
    xfsprogs
  ]);

  nix.settings.flake-registry = "";

  image = {
    baseName = lib.mkForce "nixwall-installer-${config.system.nixos.release}-${config.system.nixos.version}-${pkgs.stdenv.hostPlatform.system}";
    extension = "iso";
  };

  environment.systemPackages = [
    installerPkg
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
