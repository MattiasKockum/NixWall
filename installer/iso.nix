{
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
    modules/greeter.nix
    modules/service-flake-copy.nix
  ];

  isoImage.contents = [
    {
      source = ./nixos;
      target = "/nixwall";
    }
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
