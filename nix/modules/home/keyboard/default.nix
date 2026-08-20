# Keyboard group: remappers and input methods.
{ lib, ... }:
{
  options.dotfiles.keyboard = {
    karabiner.enable = lib.mkEnableOption "Karabiner-Elements (macOS)";
    fcitx5.enable = lib.mkEnableOption "fcitx5 input method with rime (Linux)";
  };

  imports = [
    ./karabiner.nix
    ./fcitx5.nix
    ./hammerspoon.nix
  ];
}
