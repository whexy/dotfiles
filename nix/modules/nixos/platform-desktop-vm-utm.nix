# Hardware config for UTM (QEMU-based virtualization)
# Supports both x86_64 and aarch64 architectures
# Build image with: just build-desktop utm [x86_64|aarch64]
{
  modulesPath,
  ...
}:

{
  imports = [
    ./platform-desktop-vm-base.nix
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Ensure virtio-gpu driver is loaded for display output in UTM
  boot.initrd.kernelModules = [ "virtio_gpu" ];

  boot.kernelModules = [
    "virtio_console"
    "virtio_rng"
  ];

  # QEMU guest services
  services.qemuGuest.enable = true;

  # SPICE agent for clipboard sharing and dynamic display resolution
  services.spice-vdagentd.enable = true;
}
