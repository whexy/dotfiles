# Keyboard NixOS configuration: kanata remapper and fcitx5 input method.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.keyboard;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.fcitx5.enable {
      i18n.inputMethod = {
        enable = true;
        type = "fcitx5";
        fcitx5.waylandFrontend = true;
        fcitx5.addons = with pkgs; [
          fcitx5-fluent
          (fcitx5-rime.override {
            rimeDataPkgs = [ pkgs.rime-ice ];
          })
        ];
      };
    })

    # Kanata: remap CapsLock to Hyper / Hangul,
    #         remap Tab to Meh / Tab.
    # Uses tap-hold-press so the modifier activates instantly when another
    # key is pressed, and the tap fires on release if pressed alone.
    # CapsLock tap emits Hangul (evdev KEY_HANGEUL=122, XKB keysym Hangul)
    # which fcitx5 uses as the input method toggle — mimicking macOS
    # CapsLock input switching.
    # This mirrors the Karabiner setup on macOS.
    (lib.mkIf cfg.kanata.enable {
      services.kanata = {
        enable = true;
        keyboards.default = {
          devices = [ ]; # empty = all keyboards
          extraDefCfg = "process-unmapped-keys yes";
          config = ''
            (deflocalkeys-linux
              hgl 122  ;; KEY_HANGEUL: no built-in alias in kanata on Linux
            )
            (defsrc
              caps tab
            )
            (defvar
              tap-time 200
              hold-time 200
            )
            (defalias
              hyper (tap-hold-press $tap-time $hold-time hgl (multi lctl lalt lsft lmet))
              meh   (tap-hold-press $tap-time $hold-time tab  (multi lctl lalt lmet))
            )
            (deflayer default
              @hyper @meh
            )
          '';
        };
      };
    })
  ];
}
