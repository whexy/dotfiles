# GTX 1660 Super (Turing) beside the Alder Lake iGPU. The monitor is wired to
# the iGPU, so the desktop renders there and the Nvidia card serves CUDA,
# containers, and apps launched through PRIME offload (`nvidia-offload`).
{ config, ... }:
{
  services.xserver.videoDrivers = [
    "modesetting"
    "nvidia"
  ];

  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # Turing is the oldest generation the open kernel module supports.
    open = true;
    modesetting.enable = true;
    nvidiaSettings = false;
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  hardware.nvidia-container-toolkit.enable = config.dotfiles.virtualization.docker.enable;
}
