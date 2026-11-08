# Keyboard group: system-level remappers, input methods, and automation.
# The home keyboard group configures Karabiner and fcitx5 where these are on.
{ lib, ... }:
{
  options.dotfiles.keyboard = {
    kanata.enable = lib.mkEnableOption "kanata keyboard remapper (Linux)";
    fcitx5.enable = lib.mkEnableOption "fcitx5 input method framework (Linux)";
    karabiner.enable = lib.mkEnableOption "the Karabiner-Elements app (macOS)";
  };
}
