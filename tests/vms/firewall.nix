{ lib, ... }: {
  virtualisation = {
    useEFIBoot = true;
    qemu.networkingOptions = lib.mkForce [ ];
    interfaces = {
      eth0.vlan = 1;
      eth1.vlan = 2;
    };
  };
  users.users.root.hashedPasswordFile = lib.mkForce null;
}
