{pkgs, ...}:
pkgs.testers.runNixOSTest {
  name = "Test that the VM correctly offers DHCP";

  nodes.nixwall = {...}: {
    imports = [
      ../virtual-machines/light-firewall-vm.nix
      ../../modules/nixwall-options.nix
      ../../modules/network.nix
    ];

    environment.systemPackages = with pkgs; [dig];

    nixwall.config = {
      version = 1;

      interfaces = {
        LAN = "eth0";
        WAN = "eth1";
      };

      network = {
        hostname = "nixwall";
        addresses = {
          LAN = "10.10.10.1/24";
          WAN = "10.100.100.1/24";
        };
        gateway = "10.100.100.254";
        dns = ["10.100.100.101"];
      };
    };
  };

  nodes.dns = {...}: {
    imports = [
      ../virtual-machines/dns.nix
      ../modules/dns.nix
    ];
  };

  testScript = ''
    start_all()

    nixwall.wait_for_unit("multi-user.target")
    dns.wait_for_unit("multi-user.target")

    nixwall.succeed("dig website.net | grep 10.100.100.100")
  '';
}
