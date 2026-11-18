# Keyboard group: system-level remappers, input methods, and automation.
# The home keyboard group configures Karabiner and fcitx5 where these are on.
{ lib, ... }:
{
  options.dotfiles.keyboard = {
    kanata.enable = lib.mkEnableOption "kanata keyboard remapper (Linux)";
    fcitx5.enable = lib.mkEnableOption "fcitx5 input method framework (Linux)";
    dictation.enable = lib.mkEnableOption ''
      dictation on the right Alt key in fcitx5, through wetype-asr: the
      Linux counterpart of WeType for macOS on the right Option key (Linux)'';
    karabiner.enable = lib.mkEnableOption "the Karabiner-Elements app (macOS)";
  };
}
