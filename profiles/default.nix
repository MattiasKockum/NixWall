{pkgs, ...}: {
  imports = [
    ../modules/nixwall-options.nix
    ../modules/locale.nix
    ../modules/network.nix
    ../modules/dhcp.nix
    ../modules/firewall-rules.nix
    ../modules/ssh.nix
    ../modules/nat.nix
    ../modules/dns.nix
    ../modules/users.nix
    ../modules/api.nix
    ../modules/dashboard.nix
    ../modules/git.nix
    ../modules/boot.nix
  ];

  environment.systemPackages = with pkgs; [
    gnumake
    vim
  ];

  system.stateVersion = "25.05";
  nix.settings.experimental-features = ["nix-command" "flakes"];

  services.dashboard.enable = true;
}
