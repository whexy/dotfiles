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
