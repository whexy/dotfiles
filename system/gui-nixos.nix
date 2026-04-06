# GUI NixOS system configuration
{ pkgs, username, ... }:
{
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

  fonts.packages = [
    (pkgs.nerd-fonts.fira-code)
    (pkgs.nerd-fonts.jetbrains-mono)
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-cjk-serif
  ];

  fonts.fontconfig.defaultFonts = {
    monospace = [ "FiraCode Nerd Font" ];
  };

  fonts.fontconfig.localConf = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <!-- Default sans-serif font for Chinese (Simplified) -->
      <match>
        <test name="lang" compare="contains">
          <string>zh</string>
        </test>
        <test name="family">
          <string>sans-serif</string>
        </test>
        <edit name="family" mode="prepend">
          <string>Noto Sans CJK SC</string>
        </edit>
      </match>

      <!-- Default serif font for Chinese (Simplified) -->
      <match>
        <test name="lang" compare="contains">
          <string>zh</string>
        </test>
        <test name="family">
          <string>serif</string>
        </test>
        <edit name="family" mode="prepend">
          <string>Noto Serif CJK SC</string>
        </edit>
      </match>

      <!-- Default monospace font for Chinese (Simplified) -->
      <match>
        <test name="lang" compare="contains">
          <string>zh</string>
        </test>
        <test name="family">
          <string>monospace</string>
        </test>
        <edit name="family" mode="prepend">
          <string>Noto Sans CJK SC</string>
        </edit>
      </match>
    </fontconfig>
  '';

  # GNOME Keyring: implements the Secret portal for apps that need credentials
  services.gnome.gnome-keyring.enable = true;

  # XDG Desktop Portal: provides file chooser, screen cast, notifications, etc.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
    config.common.default = [ "gnome" ];
  };

  # Required for xdg-desktop-portal with home-manager
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  # Greetd display manager with auto-login to niri
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
        user = "greeter";
      };
      initial_session = {
        command = "niri-session";
        user = username;
      };
    };
  };

  # OBS Studio with virtual camera support
  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;
    plugins = with pkgs.obs-studio-plugins; [
      obs-websocket
      obs-vaapi # VA-API hardware encoder (AMD/Intel)
    ];
  };

  # 1Password GUI
  programs._1password-gui.enable = true;

  # Kanata: remap CapsLock to Hyper / Hangul,
  #         remap Tab to Meh / Tab.
  # Uses tap-hold-press so the modifier activates instantly when another
  # key is pressed, and the tap fires on release if pressed alone.
  # CapsLock tap emits Hangul (evdev KEY_HANGEUL=122, XKB keysym Hangul)
  # which fcitx5 uses as the input method toggle — mimicking macOS
  # CapsLock input switching.
  # This mirrors the Karabiner setup on macOS.
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
}
