{ pkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "unit/users";

  nodes.nixwall = { ... }: {
    imports = [
      ../../vms/firewall.nix
      ../../../modules/nixwall.nix
    ];
    nixwall = {
      enable = true;
      config = {
        version = 1;
        usersDefaults.initialPassword = "changeme";
        users = {
          alice = {
            wheel = true;
            passwordlessSudo = true;
          };
          bob = {
            groups = [ "developers" ];
          };
        };
      };
    };
  };

  testScript = ''
    start_all()
    nixwall.wait_for_unit("multi-user.target")

    nixwall.succeed("getent passwd alice")
    nixwall.succeed("getent passwd bob")

    nixwall.succeed("getent group wheel")
    nixwall.succeed("getent group developers")

    nixwall.succeed("id -nG alice | tr ' ' '\\n' | grep -x wheel")
    nixwall.succeed("id -nG bob   | tr ' ' '\\n' | grep -x developers")

    nixwall.fail("id -nG alice | tr ' ' '\\n' | grep -x developers")
    nixwall.fail("id -nG bob   | tr ' ' '\\n' | grep -x wheel")

    nixwall.succeed("test -d /home/alice")
    nixwall.succeed("test -d /home/bob")

    nixwall.succeed("awk -F: '$1==\"alice\"{print $2}' /etc/shadow | grep -Ev '^(\\\\!|\\\\*|)$'")
    nixwall.succeed("awk -F: '$1==\"bob\"{print $2}'   /etc/shadow | grep -Ev '^(\\\\!|\\\\*|)$'")

    nixwall.succeed("sudo -u alice sudo -n id -un | grep -x root")

    nixwall.fail("sudo -u bob sudo -n id -un")

    nixwall.succeed("sudo -u alice id -un | grep -x alice")
  '';
}
