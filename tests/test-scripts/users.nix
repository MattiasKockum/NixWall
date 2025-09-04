{pkgs, ...}:
pkgs.testers.runNixOSTest {
  name = "Test that the VM correctly sets up users";

  nodes.nixwall = {...}: {
    imports = [
      ../virtual-machines/light-firewall-vm.nix
      ../../modules/nixwall-options.nix
      ../../modules/users.nix
    ];
    nixwall.config = {
      version = 1;
      usersDefaults = {initialPassword = "changeme";};
      users = {
        alice = {wheel = true;};
        bob = {groups = ["developers"];};
      };
    };
  };

  testScript = ''
    start_all()

    nixwall.wait_for_unit("multi-user.target")

    # Users exist
    nixwall.succeed("getent passwd alice")
    nixwall.succeed("getent passwd bob")

    # Groups exist (wheel is standard, developers is created)
    nixwall.succeed("getent group wheel")
    nixwall.succeed("getent group developers")

    # Memberships are correct
    nixwall.succeed("id -nG alice | tr ' ' '\\n' | grep -x wheel")
    nixwall.succeed("id -nG bob   | tr ' ' '\\n' | grep -x developers")

    # Homes created
    nixwall.succeed("test -d /home/alice")
    nixwall.succeed("test -d /home/bob")

    # Initial passwords applied: shadow entries are non-empty and not locked (! or *)
    nixwall.succeed("awk -F: '$1==\"alice\"{print $2}' /etc/shadow | grep -Ev '^(\\\\!|\\\\*|)$'")
    nixwall.succeed("awk -F: '$1==\"bob\"{print $2}'   /etc/shadow | grep -Ev '^(\\\\!|\\\\*|)$'")

    # As root we can run a command as alice without a password prompt
    nixwall.succeed("sudo -u alice id -un | grep -x alice")
  '';
}
