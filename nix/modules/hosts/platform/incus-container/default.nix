# Incus system container guest platform.
{ lib, ... }:
{
  options.dotfiles.platform.incusContainer.enable =
    lib.mkEnableOption "the Incus system container guest platform";
}
