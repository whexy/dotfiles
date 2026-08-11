{ lib, ... }:
{
  options.dotfiles.gaming = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable gaming on the system.
      '';
    };
  };
}
