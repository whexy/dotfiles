# Desktop VM platform shared by UTM and VMware images.
{ lib, ... }:
{
  options.dotfiles.platform.desktopVm = {
    enable = lib.mkEnableOption "a desktop VM platform";
    backend = lib.mkOption {
      type = lib.types.enum [
        "utm"
        "vmware"
      ];
      default = "vmware";
      description = "Desktop VM backend.";
    };
  };
}
