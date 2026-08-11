{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.platform.desktopVm;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        system.stateVersion = "25.11";

        boot = {
          loader.systemd-boot.enable = true;
          loader.efi.canTouchEfiVariables = false;
          growPartition = true;
        };

        hardware.graphics.enable = true;

        fileSystems."/" = lib.mkDefault {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
          autoResize = true;
        };
        fileSystems."/boot" = lib.mkDefault {
          device = "/dev/disk/by-label/ESP";
          fsType = "vfat";
        };
      }

      (lib.mkIf (cfg.backend == "utm") {
        boot = {
          initrd.availableKernelModules = [
            "virtio_net"
            "virtio_pci"
            "virtio_mmio"
            "virtio_blk"
            "virtio_scsi"
            "virtiofs"
            "9p"
            "9pnet_virtio"
          ];
          initrd.kernelModules = [
            "virtio_balloon"
            "virtio_console"
            "virtio_rng"
            "virtio_gpu"
          ];
          kernelModules = [
            "virtio_console"
            "virtio_rng"
          ];
        };

        services = {
          qemuGuest.enable = true;
          spice-vdagentd.enable = true;
        };
      })

      (lib.mkIf (cfg.backend == "vmware") {
        # Disable cap-provided networking through its feature options; VMware
        # uses networkd and runs behind host NAT.
        dotfiles.network = {
          networkmanager.enable = lib.mkForce false;
          firewall.enable = lib.mkForce false;
        };

        image.modules.vmware = {
          vmware.baseImageSize = "auto";
          vmware.vmSubformat = "monolithicSparse";
          virtualisation.vmware.guest = {
            enable = true;
            headless = false;
          };
        };

        virtualisation.vmware.guest = {
          enable = true;
          headless = false;
        };

        networking = {
          useNetworkd = true;
          useDHCP = false;
        };

        systemd.network = {
          enable = true;
          networks."10-wired" = {
            matchConfig.Type = "ether";
            networkConfig = {
              DHCP = "yes";
              IPv6AcceptRA = true;
              DNS = [
                "1.1.1.1"
                "8.8.8.8"
              ];
            };
          };
        };

        services.resolved = {
          enable = true;
          settings.Resolve.DNSSEC = "false";
        };

        boot = {
          initrd.availableKernelModules = [
            "mptspi"
            "ahci"
            "sd_mod"
            "sr_mod"
          ];
          initrd.kernelModules = lib.optionals pkgs.stdenv.hostPlatform.isx86 [ "vmw_pvscsi" ];
          kernelModules = [
            "vmw_balloon"
            "vmw_vmci"
          ];
        };
      })
    ]
  );
}
