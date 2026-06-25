{
  description = "Your NixWall flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixwall = {
      url = "github:MattiasKockum/NixWall";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixwall,
      disko,
      ...
    }@inputs:
    {

      nixosConfigurations.nixwall = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs self; };
        modules = [
          disko.nixosModules.disko
          nixwall.nixosModules.nixwall
          ./disko.nix
          ./configuration.nix
        ];
      };
    };
}
