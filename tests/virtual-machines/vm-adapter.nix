{
  lib,
  nixpkgs,
  ...
}: {
  imports = [(nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix")];

  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
    useOSProber = false;
  };

  virtualisation = {
    useDefaultFilesystems = true;
    qemu.networkingOptions = lib.mkForce [];
    interfaces = {
      eth0.vlan = 1;
      eth1.vlan = 2;
    };
  };

  services.qemuGuest.enable = true;
}
