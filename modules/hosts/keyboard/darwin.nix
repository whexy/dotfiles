{ config, lib, ... }:
{
  config = lib.mkIf config.dotfiles.keyboard.karabiner.enable {
    homebrew.casks = [ "karabiner-elements" ];
  };
}
