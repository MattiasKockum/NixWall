{ lib, config, ... }:
{
  config = lib.mkIf (config.nixwall.enable && config.nixwall.appliance.enable) {

    assertions = [
      {
        assertion = config.boot.loader.grub.devices == [ "nodev" ];
        message = ''
          nixwall: boot.loader.grub.devices must be [ "nodev" ]. A BIOS boot
          partition (type EF02) in your disko.nix makes disko add the disk
          device. NixWall only supports UEFI.
          Please remove the EF02 partition.
        '';
      }
    ];

    boot = {
      loader = {
        grub = {
          enable = true;
          efiSupport = true;
          efiInstallAsRemovable = true;
          device = "nodev";
          configurationLimit = lib.mkDefault 10;
        };
        efi.canTouchEfiVariables = false;
        timeout = lib.mkDefault 3;
      };

      initrd.availableKernelModules = [
        "virtio_pci"
        "virtio_blk"
        "virtio_scsi"
        "ahci"
        "nvme"
        "sd_mod"
        "xhci_pci"
        "usb_storage"
        "uas"
      ];
    };

    hardware = {
      enableRedistributableFirmware = true;
      cpu.intel.updateMicrocode = lib.mkDefault true;
      cpu.amd.updateMicrocode = lib.mkDefault true;
    };
  };
}
