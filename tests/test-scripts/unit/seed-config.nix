{ pkgs, ... }:
let
  cfgs = import ../../configs { inherit pkgs; };
in
pkgs.testers.runNixOSTest {
  name = "unit/seed-config";

  nodes.machine = { ... }: {
    imports = [
      ../../vms/firewall.nix
      ../../../modules/nixwall.nix
    ];

    nixwall = {
      enable = true;
      appliance.enable = true;
      appliance.seedEtc.enable = true;
      config = cfgs.base;
    };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("nixwall-seed-etc.service")

    machine.succeed("test -s /etc/nixos/flake.nix")
    machine.succeed("test -s /etc/nixos/flake.lock")
    machine.succeed("test -s /etc/nixos/modules/nixwall.nix")

    machine.succeed("${pkgs.git}/bin/git -C /etc/nixos rev-parse --is-inside-work-tree | grep -x true")
    machine.succeed("${pkgs.git}/bin/git -C /etc/nixos log --oneline -1 | grep 'first NixWall commit'")

    machine.fail("test -e /etc/nixos/tests")
    machine.fail("test -e /etc/nixos/.pre-commit-config.yaml")

    machine.succeed("touch /etc/nixos/test-write && rm /etc/nixos/test-write")
  '';
}
