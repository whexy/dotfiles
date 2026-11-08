# WSL guest platform: Windows owns the hardware and the network stack.
{ lib, ... }:
{
  options.dotfiles.platform.wsl = {
    enable = lib.mkEnableOption "the WSL guest platform";
    nvidia.enable = lib.mkEnableOption "CUDA and Docker GPU access through the Windows host's Nvidia driver";
  };
}
