{pkgs, ...}:
pkgs.testers.runNixOSTest {
  name = "Test the /etc/nixos directory has been seeded";

  nodes.machine = {...}: {
    imports = [
      ../virtual-machines/light-firewall-vm.nix
      ../../modules/seed-config.nix
    ];
    nixwall.seedEtc.enable = true;
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    machine.succeed("test -s /etc/nixos/flake.nix")
    machine.succeed("test -s /etc/nixos/flake.lock")
    machine.succeed("test -s /etc/nixos/config.json")
    machine.succeed("test -s /etc/nixos/modules/network.nix")

    machine.succeed("${pkgs.git}/bin/git -C /etc/nixos rev-parse --is-inside-work-tree | grep -x true")
    machine.succeed("${pkgs.git}/bin/git -C /etc/nixos log --oneline -1 | grep 'first NixWall commit'")
  '';
}
