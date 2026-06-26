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
in
{

  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    modules/greeter.nix
    modules/service-flake-copy.nix
  ];

  isoImage.contents = [
    {
      source = ./nixos;
      target = "/nixwall";
    }
  ];

  isoImage.storeContents = [
    self.packages.x86_64-linux.nixwall-api
  ];

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
