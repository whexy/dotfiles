# Keyboard group: system-level remappers and input methods.
# Mirrors the home keyboard group (Karabiner/fcitx5 user config).
{ lib, ... }:
{
  options.dotfiles.keyboard = {
    kanata.enable = lib.mkEnableOption "kanata keyboard remapper (Linux)";
    fcitx5.enable = lib.mkEnableOption "fcitx5 input method framework (Linux)";
  };
}
