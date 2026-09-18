{ config, lib, ... }:
let
  cfg = config.dotfiles.platform.qemuGuest;
in
{
  config = lib.mkIf cfg.enable {
    system.stateVersion = "25.11";

    boot = {
      loader.systemd-boot.enable = true;
      loader.efi.canTouchEfiVariables = true;

      # Common QEMU virtio profile plus the disk/controller modules used by
      # this image. Kept here so the platform remains option-gated.
      initrd.availableKernelModules = [
        "virtio_net"
        "virtio_pci"
        "virtio_mmio"
        "virtio_blk"
        "virtio_scsi"
        "virtiofs"
        "9p"
        "9pnet_virtio"
        "uhci_hcd"
        "ehci_pci"
        "ahci"
        "sd_mod"
        "sr_mod"
      ];
      initrd.kernelModules = [
        "virtio_balloon"
        "virtio_console"
        "virtio_rng"
        "virtio_gpu"
      ];
    };

    services.qemuGuest.enable = true;

    disko.devices.disk.main = {
      type = "disk";
      device = "/dev/sda";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [
                "fmask=0022"
                "dmask=0022"
              ];
              extraArgs = [
                "-n"
                "NIXBOOT"
              ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
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
