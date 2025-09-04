_: {
  boot.loader.grub.enable = true;

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "ahci"
    "sd_mod"
    "xhci_pci"
  ];

  hardware.enableRedistributableFirmware = true;
}
