# Hardware config for QEMU x86_64 VMs with GUI / Wayland support
# Extends qemu-x86_64 with virtio-gpu, hardware graphics, and SPICE agent.
# Used for hosts that run a Wayland compositor (e.g. niri) inside a QEMU/Proxmox VM,
# including GPU passthrough setups (e.g. AMD RX 6000 series requiring firmware blobs).
_:

{
  # Load virtio-gpu early so the display is available before the compositor starts
  boot.initrd.kernelModules = [ "virtio_gpu" ];

  # Monitor declarations consumed by compositor configs.
  dotfiles.hardware.monitors = [
    {
      connector = "HDMI-A-1";
      resolution = {
        width = 3840;
        height = 2160;
      };
      refreshRate = 120.000;
      scale = 1.5;
    }
  ];

  hardware = {
    # Enable DRM/KMS and OpenGL support required by Wayland compositors
    # Mesa (pulled in by enable = true) includes the radeonsi VA-API backend and
    # RADV Vulkan driver, which together enable hardware encoding in OBS via obs-vaapi.
    graphics.enable = true;

    # Include redistributable firmware needed for GPU passthrough
    enableRedistributableFirmware = true;

    # Enable udev rules files
    logitech.wireless.enable = true;

    # Bluetooth support
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Experimental = true;
          FastConnectable = true;
        };
        Policy = {
          AutoEnable = true;
        };
      };
    };
  };

  # Use the powersave CPU frequency governor to reduce idle power draw.
  powerManagement.cpuFreqGovernor = "powersave";

  services = {
    # SPICE agent: dynamic display resolution + clipboard sharing via Proxmox noVNC
    spice-vdagentd.enable = true;

    # Suspend the system after 20 minutes of logind-detected idleness.
    logind.settings.Login = {
      IdleAction = "suspend";
      IdleActionSec = "20min";
    };
  };
}
