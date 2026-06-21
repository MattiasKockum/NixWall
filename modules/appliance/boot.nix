{ lib, config, ... }: {
  config = lib.mkIf (config.nixwall.enable && config.nixwall.appliance.enable) {
    boot = {
      loader = {
        grub = {
          enable = true;
          devices = [ "nodev" ];
          efiSupport = true;
          efiInstallAsRemovable = lib.mkDefault true;
        };
        efi.canTouchEfiVariables = false;
      };
      initrd.availableKernelModules = [
        "virtio_pci"
        "virtio_blk"
        "virtio_scsi"
        "ahci"
        "sd_mod"
        "xhci_pci"
        "nvme"
        "usb_storage"
      ];
    };
    hardware.enableRedistributableFirmware = true;
  };
}
