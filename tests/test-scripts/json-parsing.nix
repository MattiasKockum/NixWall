{
  pkgs,
  self,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "Test that the VM correctly sets up its IP addresses";

  nodes.nixwall = {...}: {
    _module.args = {inherit self;};
    imports = [
      ../virtual-machines/light-firewall-vm.nix
      ../../modules/nixwall-options.nix
      ../../modules/network.nix
    ];
  };

  testScript = ''
    start_all()

    nixwall.wait_for_unit("multi-user.target")

    nixwall.succeed("ip -o -4 addr show dev eth0 | grep -x '.* 10.10.10.1/24 .*'")
    nixwall.succeed("ip -o -4 addr show dev eth1 | grep -x '.* 10.100.100.1/24 .*'")
    nixwall.succeed("ip route | grep -x '.*default via 10.100.100.254 dev eth1 proto static.*'")
  '';
}
