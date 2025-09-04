{
  lib,
  pkgs,
  self,
  nixpkgs,
  ...
}: let
  baseSystem = nixpkgs.lib.nixosSystem {
    inherit (pkgs.stdenv.hostPlatform) system;
    modules = [
      (self + "/tests/virtual-machines/vm-adapter.nix")
      (self + "/profiles/default.nix")
      {system.includeBuildDependencies = true;}
    ];
    specialArgs = {inherit self nixpkgs;};
  };

  toPaths = ci: let
    raw = lib.splitString "\n" (builtins.readFile "${ci}/store-paths");
  in
    lib.unique (builtins.filter (p: p != "" && lib.hasPrefix "/" p) raw);

  sysClosure = pkgs.closureInfo {
    rootPaths = [
      baseSystem.config.system.build.toplevel
    ];
  };
in {
  virtualisation.additionalPaths = toPaths sysClosure;
}
