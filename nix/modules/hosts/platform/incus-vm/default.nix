# Incus virtual machine guest platform.
{ lib, ... }:
{
  options.dotfiles.platform.incusVm.enable =
    lib.mkEnableOption "the Incus virtual machine guest platform";
}
