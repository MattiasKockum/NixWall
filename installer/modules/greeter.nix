{
  lib,
  pkgs,
  ...
}: let
  nixwallHelpText = ''
    Here are the necessary informations to install NixWall on your system step by step.
    Please read them carefully before continuing.


    - You can always get that helper back by running 'nixwall-help'
    - The installer doesn't need access to the internet.
    - The "nixos" and "root" accounts have empty passwords.
    - By default the keyboard is set to qwerty. For instance, run `loadkeys fr` to switch to azerty during installation.
    - vim and nano are available.
    - The flake targeted for installation has been copied automatically from /iso to /root to be edited there before installation.
    - Run `lsblk` to see what your disks are. Then, edit the file under `/root/etc/nixos/installer/disko.nix` accordingly.
    - Run `ip link` to see your interfaces. Then, edit the file under `/root/etc/nixos/config.json` accordingly.
    - Don't forget to edit '/root/etc/nixos/config.json' locale values.
    - By default, the config.json holds a lot of boilerplate, feel free to remove them as much as you want.
    - The default password is "changeme" and the default user is "alice".
    - Run `nixwall-install` to start the installation, then 'reboot'.
  '';

  nixwallHelpFile = pkgs.writeText "nixwall-help.txt" nixwallHelpText;

  nixwallHelpCmd = pkgs.writeShellScriptBin "nixwall-help" ''
    cat ${nixwallHelpFile}
  '';
in {
  environment.systemPackages = [
    nixwallHelpCmd
  ];

  services.getty.autologinUser = lib.mkForce "root";
  services.getty.greetingLine = "";
  environment.etc."issue".text = ''
    \e[1;32m
    ┌──────────────────────────────────┐
    │ Welcome to the NixWall Installer │
    └──────────────────────────────────┘
    \e[0m

    ${nixwallHelpText}
  '';
}
