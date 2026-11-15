# Incus system container guest platform.
{ lib, ... }:
{
  options.dotfiles.platform.incusContainer = {
    enable = lib.mkEnableOption "the Incus system container guest platform";
    nvidia.enable = lib.mkEnableOption ''
      the Incus host's Nvidia GPU, passed through with
      `incus config device add <instance> gpu gpu`,
      `incus config set <instance> nvidia.runtime=true` and
      `incus config set <instance> nvidia.driver.capabilities=all`. The
      nvidia runtime bind-mounts the host driver's libraries into /usr/lib64
      and its tools (nvidia-smi, ...) into /usr/bin at instance start, so the
      container ships no driver of its own. Without `all` it mounts only
      CUDA's: no Vulkan, EGL or NVENC
    '';
  };
}
