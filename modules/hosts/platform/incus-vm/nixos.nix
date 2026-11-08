{ config, lib, ... }:
let
  cfg = config.dotfiles.platform.incusVm;
  inherit (config.dotfiles.host) hostName;

  # All features the Incus 6.20+ guest agent understands. The agent binary is
  # injected by the hypervisor at boot, so the hypervisor's Incus version
  # decides whether the feature map is honored at all.
  agentFeatures = {
    guestapi = true; # /dev/incus API inside the guest
    exec = true; # incus exec
    files = true; # incus file push/pull
    mounts = true; # shared disk devices
    metrics = true; # OpenMetrics endpoint
    state = true; # OS/network state shown by incus list (incl. IPs)
  }
  // lib.optionalAttrs cfg.untrustedHypervisor {
    exec = false;
    files = false;
    state = false;
  }
  // cfg.agent.features;
in
{
  config = lib.mkIf cfg.enable {
    disko = {
      imageBuilder.imageFormat = "qcow2";

      devices.disk.main = lib.mkIf cfg.encryptedDisk.enable {
        type = "disk";
        device = "/dev/sda";
        imageName = hostName;
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
                passwordFile = "/tmp/${hostName}-luks-passphrase";
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
    };

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

    # Read once at agent startup; applies after incus-agent restart or reboot.
    environment.etc."incus-agent.yml".text = ''
      # Managed by NixOS via dotfiles.platform.incusVm.agent.features.
      features:
      ${lib.concatMapAttrsStringSep "\n" (
        name: value: "  ${name}: ${lib.boolToString value}"
      ) agentFeatures}
    '';
  };
}
