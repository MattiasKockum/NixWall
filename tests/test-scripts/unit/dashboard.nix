{ pkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "unit/dashboard";

  nodes.nixwall = { ... }: {
    imports = [
      ../../vms/firewall.nix
      ../../../modules/nixwall.nix
    ];
    nixwall = {
      enable = true;
      appliance = {
        enable = true;
        dashboard.enable = true;
      };
      config = {
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
          dns = [ "10.100.100.10" ];
        };
        firewall.rules = [
          {
            name = "dashboard";
            from = "LAN";
            to = "FW";
            proto = "tcp";
            ports = 80;
            action = "accept";
          }
        ];
      };
    };
  };

  nodes.client = { ... }: {
    imports = [ ../../vms/client.nix ];
    networking = {
      useNetworkd = true;
      networkmanager.enable = false;
      useDHCP = false;
      interfaces.eth0.ipv4.addresses = [
        {
          address = "10.10.10.2";
          prefixLength = 24;
        }
      ];
      defaultGateway = {
        address = "10.10.10.1";
        interface = "eth0";
      };
    };
  };

  testScript = ''
    start_all()

    nixwall.wait_for_unit("multi-user.target")
    nixwall.wait_for_unit("nixwall-dashboard.service")
    nixwall.wait_until_succeeds("ss -ltn '( sport = :80 )' | grep -F LISTEN")

    client.wait_for_unit("multi-user.target")
    client.wait_until_succeeds("ip addr show dev eth0 | grep '10.10.10.2'")

    client.wait_until_succeeds("curl -sSf --max-time 5 http://10.10.10.1:80")

    nixwall.fail("curl -sf --max-time 3 http://10.100.100.1:80")
  '';
}
