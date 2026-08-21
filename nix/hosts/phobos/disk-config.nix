{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    imageName = "phobos";
    imageSize = "32G";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
            extraArgs = [
              "-n"
              "NIXBOOT"
            ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "luks";
            name = "crypted";
            # Supplied to the Disko image builder with --pre-format-files.
            # It is used only to create the image and is not stored in it.
            passwordFile = "/tmp/phobos-luks-passphrase";
            settings.allowDiscards = true;
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "noatime" ];
              extraArgs = [
                "-L"
                "NIXROOT"
              ];
            };
          };
        };
      };
    };
  };
}
