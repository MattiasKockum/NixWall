{
  disko.devices = {
    disk.disk1 = {
      device = "/dev/nvme0n1"; # CHANGE ME
      type = "disk";
      content = {
        type = "gpt";
        partitions = {

          esp = {
            name = "ESP";
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [
                "umask=0077"
                "defaults"
              ];
            };
          };

          root = {
            name = "root";
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "noatime" ];
            };
          };

        };
      };
    };
  };
}
