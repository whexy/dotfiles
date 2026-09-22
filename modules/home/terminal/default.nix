# Terminal group: emulators and multiplexers.
{ lib, ... }:
{
  options.dotfiles.terminal = {
    ghostty.enable = lib.mkEnableOption "the Ghostty terminal emulator";
    tmux.enable = lib.mkEnableOption "tmux";
    zellij.enable = lib.mkEnableOption "zellij";
    adopt.enable = lib.mkEnableOption "totmux/tozellij job adoption wrappers (Linux)";
  };

  imports = [
    ./adopt.nix
    ./cmux.nix
    ./ghostty.nix
    ./tmux.nix
    ./zellij.nix
  ];
}
