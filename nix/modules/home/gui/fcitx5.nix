# Fcitx5 input method configuration (Linux)
#
# Rime is configured to use double_pinyin_flypy (Xiaohe Shuangpin) via rime-ice.
# The default.custom.yaml tells rime to load the flypy schema on deploy.
#
# CapsLock tap is remapped to Hangul via kanata (see nix/modules/nixos/gui.nix),
# and fcitx5 is configured here to use Hangul as the input method toggle key.
{
  lib,
  darwin,
  ...
}:
lib.mkIf (!darwin) {
  # Rime configuration: use Xiaohe Shuangpin (flypy) with rime-ice
  xdg.dataFile."fcitx5/rime/default.custom.yaml".text = ''
    patch:
      __include: rime_ice_suggestion:/

      schema_list:
        - schema: double_pinyin_flypy
  '';

  # Fcitx5 global config: use Hangul key to toggle input methods.
  # Kanata emits Hangul (evdev 122) on CapsLock tap, so CapsLock = switch IM.
  xdg.configFile."fcitx5/config".text = ''
    [Hotkey/TriggerKeys]
    0=Hangul
  '';
}
