{
  description = "NixWall, a modern firewall based on NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    disko,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = f: nixpkgs.lib.genAttrs systems f;
  in {
    nixosConfigurations = {
      nixwall = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./installer/disko.nix
          ./profiles/default.nix
        ];
        specialArgs = {inherit self;};
      };

      installerIso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ({modulesPath, ...}: {
            imports = [(modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")];
          })
          ./installer/iso.nix
        ];
        specialArgs = {inherit self;};
      };

      nixwallTestVM = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./profiles/default.nix
          ./tests/virtual-machines/heavy-firewall-vm.nix
          ./tests/virtual-machines/vm-adapter.nix
        ];
        specialArgs = {inherit self nixpkgs;};
      };
    };

    checks = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      "seed-config" = import ./tests/test-scripts/seed-config.nix {inherit pkgs;};
      "network" = import ./tests/test-scripts/network.nix {inherit pkgs;};
      "users" = import ./tests/test-scripts/users.nix {inherit pkgs;};
      "dashboard" = import ./tests/test-scripts/dashboard.nix {inherit pkgs;};
      "ssh" = import ./tests/test-scripts/ssh.nix {inherit pkgs;};
      "dhcp" = import ./tests/test-scripts/dhcp.nix {inherit pkgs;};
      "dns-setting" = import ./tests/test-scripts/dns-setting.nix {inherit pkgs;};
      "dns-server" = import ./tests/test-scripts/dns-server.nix {inherit pkgs;};
      "api" = import ./tests/test-scripts/api.nix {inherit pkgs;};
      "firewall-rules" = import ./tests/test-scripts/firewall-rules.nix {inherit pkgs;};
      "nat" = import ./tests/test-scripts/nat.nix {inherit pkgs;};
      "build" = import ./tests/test-scripts/build.nix {inherit pkgs nixpkgs self;};
    });
  };
}
