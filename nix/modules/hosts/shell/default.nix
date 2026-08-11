# Shell group: system shells.
{ lib, ... }:
{
  options.dotfiles.shell = {
    zsh.enable = lib.mkEnableOption "zsh as a system shell";
  };
}
