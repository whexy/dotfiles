# Hardware config for QEMU x86_64 VMs with GUI / Wayland support
# Extends qemu-x86_64 with virtio-gpu, hardware graphics, and SPICE agent.
# Used for hosts that run a Wayland compositor (e.g. niri) inside a QEMU/Proxmox VM,
# including GPU passthrough setups (e.g. AMD RX 6000 series requiring firmware blobs).
{ ... }:

{
  imports = [
    ./qemu-x86_64.nix
  ];

  # Load virtio-gpu early so the display is available before the compositor starts
  boot.initrd.kernelModules = [ "virtio_gpu" ];

  # Enable DRM/KMS and OpenGL support required by Wayland compositors
  hardware.graphics.enable = true;

  # Include redistributable firmware needed for GPU passthrough
  hardware.enableRedistributableFirmware = true;

  # Enable udev rules files
  hardware.logitech.wireless.enable = true;

  # SPICE agent: dynamic display resolution + clipboard sharing via Proxmox noVNC
  services.spice-vdagentd.enable = true;

  # Monitor declarations — consumed by compositor configs via osConfig.hardware.monitors
  # Samsung Odyssey G8 (HDMI-A-1): 4K panel, 120 Hz over HDMI
  hardware.monitors = [
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

  # Use the powersave CPU frequency governor to reduce idle power draw.
  powerManagement.cpuFreqGovernor = "powersave";

  # Suspend the system after 20 minutes of logind-detected idleness.
  services.logind.settings.Login = {
    IdleAction = "suspend";
    IdleActionSec = "20min";
  };

  # Bluetooth support
  hardware.bluetooth = {
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
}
