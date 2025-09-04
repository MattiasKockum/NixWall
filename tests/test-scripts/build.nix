{
  pkgs,
  nixpkgs,
  self,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "Test that the system can rebuild itself (offline, with config change)";

  defaults = {
    _module.args = {inherit self nixpkgs;};
  };

  nodes.nixwall = {
    #pkgs,
    #lib,
    ...
  }: {
    imports = [
      ../virtual-machines/heavy-firewall-vm.nix
      ../virtual-machines/preseeded-store.nix
      ../../profiles/default.nix
      ../../modules/seed-config.nix
    ];

    nixwall.seedEtc.enable = true;
  };

  testScript = ''
    start_all()
    nixwall.wait_for_unit("multi-user.target")

    nixwall.succeed("sed -i 's/10.100.100.1/10.100.100.2/g' /etc/nixos/config.json")
    nixwall.succeed("nixos-rebuild build --flake /etc/nixos#nixwallTestVM")
  '';
}
