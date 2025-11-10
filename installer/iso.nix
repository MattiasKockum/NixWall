{
  lib,
  pkgs,
  config,
  self,
  ...
}: let
  installerPkg = pkgs.callPackage (self + "/installer/scripts") {};
in {
  imports = [
    modules/greeter.nix
    modules/service-flake-copy.nix
  ];

  isoImage.contents = [
    {
      source = self;
      target = "/nixwall";
    }
  ];

  image = {
    baseName =
      lib.mkForce
      "nixwall-installer-${config.system.nixos.release}-${config.system.nixos.version}-${pkgs.stdenv.hostPlatform.system}";
    extension = "iso";
  };

  environment.systemPackages = [
    installerPkg
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];
}
