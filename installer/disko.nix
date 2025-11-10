{
  disko.devices = {
    disk.disk1 = {
      device = "/dev/vda"; # CHANGE ME
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          bios = {
            name = "bios";
            size = "1M";
            type = "EF02"; # BIOS boot partition for GRUB on GPT
          };
          boot = {
            name = "boot";
            size = "500M";
            type = "8300";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/boot";
            };
          };
          root = {
            name = "root";
            size = "100%";
            type = "8300";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = ["noatime"];
            };
          };
        };
      };
    };
  };
}
