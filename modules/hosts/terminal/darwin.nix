{ config, lib, ... }:
{
  config = lib.mkIf config.dotfiles.terminal.cmux.enable {
    homebrew.casks = [ "cmux" ];
  };
}
