{
  config,
  lib,
  modulesPath,
  ...
}:
let
  cfg = config.dotfiles.platform.incusVm;
in
{
  imports = [ (modulesPath + "/virtualisation/lxc-image-metadata.nix") ];

  config = lib.mkIf cfg.enable {
    disko.imageBuilder.imageFormat = "qcow2";

    boot = {
      loader.systemd-boot.enable = true;
      loader.efi.canTouchEfiVariables = true;

      # Incus exposes this console through `incus console <instance>`, so the
      # guest can be installed, unlocked, and recovered without VGA/SPICE.
      kernelParams = [
        "console=tty1"
        "console=ttyS0,115200n8"
      ];
      initrd = {
        systemd.enable = true;
        availableKernelModules = [
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
        kernelModules = [
          "virtio_balloon"
          "virtio_console"
          "virtio_rng"
        ];
      };
    };

    services.qemuGuest.enable = true;
    virtualisation.incus.agent.enable = true;
  };
}
