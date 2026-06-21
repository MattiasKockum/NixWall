{ ... }: {
  imports = [
    ./core/nixwall-options.nix
    ./core/network.nix
    ./core/dhcp.nix
    ./core/firewall-rules.nix
    ./core/ssh.nix
    ./core/dns.nix
    ./core/users.nix
    ./appliance/api.nix
    ./appliance/boot.nix
    ./appliance/certs.nix
    ./appliance/dashboard.nix
    ./appliance/git.nix
    ./appliance/locale.nix
    ./appliance/pam.nix
    ./appliance/seed-config.nix
  ];
}
