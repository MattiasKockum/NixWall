{
  description = "NixWall, a modern firewall based on NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      pre-commit-hooks,
      crane,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;

      preCommitConfig =
        system:
        pre-commit-hooks.lib.${system}.run {
          src = ./.;
          settings.rust.cargoManifestPath = "api/Cargo.toml";
          hooks = {
            nixfmt.enable = true;
            statix.enable = true;
            deadnix.enable = true;
            nil.enable = true;
            trim-trailing-whitespace.enable = true;
            end-of-file-fixer.enable = true;
            shellcheck = {
              enable = true;
              excludes = [ ".envrc" ];
            };
            rustfmt.enable = true;
            prettier.enable = true;
            markdownlint.enable = true;
            typos.enable = true;
            check-json.enable = true;
          };
        };

      craneLib = system: crane.mkLib nixpkgs.legacyPackages.${system};

      apiSrc =
        system: (craneLib system).cleanCargoSource (nixpkgs.legacyPackages.${system}.lib.cleanSource ./api);

      commonArgs =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          src = apiSrc system;
          strictDeps = true;
          buildInputs = [ pkgs.pam ];
          nativeBuildInputs = [
            pkgs.pkg-config
            pkgs.rustPlatform.bindgenHook
          ];
        };

      cargoArtifacts = system: (craneLib system).buildDepsOnly (commonArgs system);

    in
    {
      nixosModules = {
        nixwall = import ./modules/nixwall.nix;
        nixwall-options = import ./modules/core/nixwall-options.nix;
        network = import ./modules/core/network.nix;
        firewall = import ./modules/core/firewall-rules.nix;
        dhcp = import ./modules/core/dhcp.nix;
        dns = import ./modules/core/dns.nix;
        ssh = import ./modules/core/ssh.nix;
        users = import ./modules/core/users.nix;
      };

      packages = forAllSystems (
        system:
        let
          crane' = craneLib system;
        in
        {
          nixwall-api = crane'.buildPackage (
            (commonArgs system) // { cargoArtifacts = cargoArtifacts system; }
          );
          default = self.packages.${system}.nixwall-api;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            inherit (preCommitConfig system) shellHook;
            packages = with pkgs; [
              nixfmt
              statix
              deadnix
              nil
              shellcheck
              prettier
              markdownlint-cli
              typos
              cargo
              rustc
              clippy
              rustfmt
              pkg-config
              pam
            ];
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          crane' = craneLib system;
          artifacts = cargoArtifacts system;
          unit = path: import path { inherit pkgs; };
          integration = path: import path { inherit pkgs; };
        in
        {
          # Linter
          pre-commit = preCommitConfig system;

          # Rust
          nixwall-api-clippy = crane'.cargoClippy {
            src = apiSrc system;
            cargoArtifacts = artifacts;
            buildInputs = [ pkgs.pam ];
            nativeBuildInputs = [ pkgs.pkg-config ];
            cargoClippyExtraArgs = "-- -D warnings";
          };
          nixwall-api-fmt = crane'.cargoFmt {
            src = apiSrc system;
          };
          nixwall-api-build = self.packages.${system}.nixwall-api;

          # Unit
          "unit/certs" = unit ./tests/test-scripts/unit/certs.nix;
          "unit/dhcp" = unit ./tests/test-scripts/unit/dhcp.nix;
          "unit/dns-setting" = unit ./tests/test-scripts/unit/dns-setting.nix;
          "unit/network" = unit ./tests/test-scripts/unit/network.nix;
          "unit/ssh" = unit ./tests/test-scripts/unit/ssh.nix;
          "unit/users" = unit ./tests/test-scripts/unit/users.nix;
          "unit/seed-config" = unit ./tests/test-scripts/unit/seed-config.nix;
          "unit/dashboard" = unit ./tests/test-scripts/unit/dashboard.nix;

          # Integration
          "integration/nat" = integration ./tests/test-scripts/integration/nat.nix;
          "integration/firewall-rules" = integration ./tests/test-scripts/integration/firewall-rules.nix;
          "integration/dns-server" = integration ./tests/test-scripts/integration/dns-server.nix;
          "integration/api" = integration ./tests/test-scripts/integration/api.nix;
        }
      );
    };
}
