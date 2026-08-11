# Terminal group: emulators and multiplexers.
{ lib, ... }:
{
  options.dotfiles.terminal = {
    ghostty.enable = lib.mkEnableOption "the Ghostty terminal emulator";
    tmux.enable = lib.mkEnableOption "tmux";
    zellij.enable = lib.mkEnableOption "zellij";
  };

  imports = [
    ./ghostty.nix
    ./tmux.nix
    ./zellij.nix
  ];
}
