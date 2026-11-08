# Fcitx5 input method configuration (Linux)
#
# Rime is configured to use double_pinyin_flypy (Xiaohe Shuangpin) via rime-ice.
# The default.custom.yaml tells rime to load the flypy schema on deploy.
#
# CapsLock tap is remapped to Hangul via kanata (see modules/hosts/keyboard/nixos.nix),
# and fcitx5 is configured here to use Hangul as the input method toggle key.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.keyboard;
in
{
  config = lib.mkIf (cfg.fcitx5.enable && pkgs.stdenv.hostPlatform.isLinux) {
    # niri does not process XDG autostart entries.
    programs.niri.settings = lib.mkIf config.dotfiles.wm.niri.enable {
      spawn-at-startup = lib.mkAfter [
        {
          command = [
            "fcitx5"
            "-d"
          ];
        }
      ];
    };

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
  };
}
