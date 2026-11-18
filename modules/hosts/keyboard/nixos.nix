# Keyboard NixOS configuration: kanata remapper and fcitx5 input method.
{
  config,
  pkgs,
  lib,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.keyboard;
  dictate = cfg.fcitx5.enable && cfg.dictation.enable;
in
{
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.dictation.enable -> cfg.kanata.enable;
          message = "dotfiles.keyboard.dictation needs dotfiles.keyboard.kanata, which sends its key.";
        }
      ];
    }

    (lib.mkIf cfg.fcitx5.enable {
      i18n.inputMethod = {
        enable = true;
        type = "fcitx5";
        fcitx5.waylandFrontend = true;
        fcitx5.addons =
          with pkgs;
          [
            fcitx5-fluent
            (fcitx5-rime.override {
              rimeDataPkgs = [ pkgs.rime-ice ];
            })
          ]
          ++ lib.optional dictate perSystem.self.wetype-dictate;
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
    # With dictation, a lone right Super tap emits F19, the dictation addon's
    # key; a slower hold stays Super. niri takes Super shortcuts before the
    # input method sees them, so only kanata can tell a tap from one.
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
              caps tab${lib.optionalString dictate " rmet"}
            )
            (defvar
              tap-time 200
              hold-time 200
            )
            (defalias
              hyper (tap-hold-press $tap-time $hold-time hgl (multi lctl lalt lsft lmet))
              meh   (tap-hold-press $tap-time $hold-time tab  (multi lctl lalt lmet))
              ${lib.optionalString dictate "dictate (tap-hold-press $tap-time 400 f19 rmet)"}
            )
            (deflayer default
              @hyper @meh${lib.optionalString dictate " @dictate"}
            )
          '';
        };
      };
    })
  ];
}
