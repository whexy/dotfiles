# Keyboard Darwin system configuration: Hammerspoon via Homebrew cask.
{ config, lib, ... }:
let
  cfg = config.dotfiles.keyboard;
in
{
  config = lib.mkIf cfg.hammerspoon.enable {
    homebrew.casks = [ "hammerspoon" ];
  };
}
