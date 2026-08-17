{ config, lib, ... }:
let
  cfg = config.dotfiles.platform.incusVm;
in
{
  config = lib.mkIf cfg.enable {
    boot = {
      loader.systemd-boot.enable = true;
      loader.efi.canTouchEfiVariables = true;

      initrd.availableKernelModules = [
        "virtio_net"
        "virtio_pci"
        "virtio_mmio"
        "virtio_blk"
        "virtio_scsi"
        "virtiofs"
        "9p"
        "9pnet_virtio"
        "ahci"
        "sd_mod"
        "sr_mod"
      ];
      initrd.kernelModules = [
        "virtio_balloon"
        "virtio_console"
        "virtio_rng"
      ];
    };

    services.qemuGuest.enable = true;
    virtualisation.incus.agent.enable = true;
  };
}
