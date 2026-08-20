# Keyboard group: system-level remappers, input methods, and automation.
# Mirrors the home keyboard group (Karabiner/Hammerspoon/fcitx5 user config).
{ lib, ... }:
{
  options.dotfiles.keyboard = {
    kanata.enable = lib.mkEnableOption "kanata keyboard remapper (Linux)";
    fcitx5.enable = lib.mkEnableOption "fcitx5 input method framework (Linux)";
    hammerspoon.enable = lib.mkEnableOption "Hammerspoon automation tool (macOS)";
  };
}
