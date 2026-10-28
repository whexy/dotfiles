# Terminal group: emulators and multiplexers.
{ lib, ... }:
{
  options.dotfiles.terminal = {
    ghostty.enable = lib.mkEnableOption "the Ghostty terminal emulator";
    tmux.enable = lib.mkEnableOption "tmux";
    zellij.enable = lib.mkEnableOption "zellij";
    rex = {
      enable = lib.mkEnableOption "the Rex Beta terminal multiplexer app (macOS)";
      terminfo.enable = lib.mkEnableOption "Rex's xterm-rex terminfo entry, for Rex terminals that reach this machine";
    };
    adopt.enable = lib.mkEnableOption "totmux/tozellij job adoption wrappers (Linux)";
  };

  imports = [
    ./adopt.nix
    ./ghostty.nix
    ./rex.nix
    ./tmux.nix
    ./zellij.nix
  ];
}
