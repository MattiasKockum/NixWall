{ pkgs, ... }:
let
  cfgs = import ../../configs { inherit pkgs; };

  carolHash = "$6$PxUZQx/q2lPmQf.0$/my0e2zwiiYsG0K2QXcmGyOZ.PlSVhmoKGI0HlHyZmbIK.geiZG7//o1hgqGLrN9hkVdta/GegvvPfAiClxN70";
in
pkgs.testers.runNixOSTest {
  name = "unit/users";

  nodes.nixwall = { ... }: {
    imports = [
      ../../vms/firewall.nix
      ../../../modules/nixwall.nix
    ];
    nixwall = {
      enable = true;
      config = cfgs.mk [
        {
          users = {
            alice = {
              wheel = true;
              passwordlessSudo = true;
              initialPassword = "alice-start";
              ssh.authorizedKeys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPzZm9OdiwdnERpkPbcL2cLo8BX0OL+JMdTHTeyfLV/G alice@test"
              ];
            };
            bob = {
              groups = [ "developers" ];
              ssh.authorizedKeys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBtzGrILUf6GhgSWrO9dCICmqprYRWXAbnpmiYFPvWVW bob@test"
              ];
            };
            carol.passwordHash = carolHash;
            dave = { };
            root = {
              ssh.authorizedKeys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDWmjs0Zo1u+9NjrJBSi0Dsds3lTrrOsm0DfkS1b+pdz root@test"
              ];
            };
          };
        }
      ];
    };
  };

  testScript = ''
    start_all()
    nixwall.wait_for_unit("multi-user.target")

    def shadow(user):
        return nixwall.succeed(f"awk -F: '$1==\"{user}\"{{print $2}}' /etc/shadow").strip()

    for u in ["alice", "bob", "carol", "dave", "root"]:
        nixwall.succeed(f"getent passwd {u}")
    nixwall.succeed("test \"$(id -u alice)\" -ge 1000")
    nixwall.succeed("test \"$(id -u root)\" -eq 0")

    for u in ["alice", "bob", "carol", "dave"]:
        nixwall.succeed(f"test -d /home/{u}")
    nixwall.fail("test -e /home/root")
    nixwall.succeed("getent passwd root | cut -d: -f6 | grep -x /root")

    nixwall.succeed("getent group wheel")
    nixwall.succeed("getent group developers")
    nixwall.succeed("id -nG alice | tr ' ' '\\n' | grep -x wheel")
    nixwall.succeed("id -nG bob | tr ' ' '\\n' | grep -x developers")
    nixwall.fail("id -nG alice | tr ' ' '\\n' | grep -x developers")
    nixwall.fail("id -nG bob | tr ' ' '\\n' | grep -x wheel")
    nixwall.fail("id -nG dave | tr ' ' '\\n' | grep -x wheel")

    assert shadow("alice").startswith("$"), f"alice should have a hash, got {shadow('alice')!r}"
    assert shadow("carol") == "${carolHash}", f"carol hash mismatch: {shadow('carol')!r}"
    for u in ["root", "bob", "dave"]:
        f = shadow(u)
        assert f.startswith("!"), f"{u} should be locked, got {f!r}"

    nixwall.succeed("sudo -u alice sudo -n id -un | grep -x root")
    nixwall.fail("sudo -u bob sudo -n id -un")
    nixwall.fail("sudo -u dave sudo -n id -un")
    nixwall.succeed("sudo -u alice id -un | grep -x alice")
  '';
}
