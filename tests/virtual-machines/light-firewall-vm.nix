{lib, ...}: {
  # VM Network config
  virtualisation.qemu.networkingOptions = lib.mkForce [];
  virtualisation.interfaces = {
    eth0.vlan = 1;
    eth1.vlan = 2;
  };
}
