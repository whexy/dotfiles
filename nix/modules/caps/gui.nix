# gui cap preset: machines expected to have GUI environments.
_: {
  dotfiles = {
    desktop.enable = true;
    fonts.enable = true;
    # Firefox Homebrew cask; only has an effect on Darwin (on NixOS,
    # Firefox is installed by the home browser group).
    browser.firefox.enable = true;
    # PipeWire audio stack; only has an effect on NixOS.
    audio.enable = true;
    # OBS Studio with virtual camera; only has an effect on NixOS.
    streaming.enable = true;
    # Kanata remapper and fcitx5 input method; only have an effect on NixOS
    # (macOS uses Karabiner from the home keyboard group).
    keyboard.kanata.enable = true;
    keyboard.fcitx5.enable = true;
    security = {
      # GNOME Keyring and 1Password GUI; only have an effect on NixOS.
      keyring.enable = true;
      onepasswordGui.enable = true;
      # Touch ID / Apple Watch sudo; only has an effect on Darwin.
      biometricSudo.enable = true;
    };
    # Homebrew casks; only has an effect on Darwin.
    homebrew.enable = true;
  };
}
