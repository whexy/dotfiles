# gui cap preset: machines expected to have GUI environments.
{ lib, ... }: {
  dotfiles = {
    desktop.enable = lib.mkDefault true;
    fonts.enable = lib.mkDefault true;
    # Firefox Homebrew cask; only has an effect on Darwin (on NixOS,
    # Firefox is installed by the home browser group).
    browser.firefox.enable = lib.mkDefault true;
    # PipeWire audio stack; only has an effect on NixOS.
    audio.enable = lib.mkDefault true;
    # OBS Studio with virtual camera; only has an effect on NixOS.
    streaming.enable = lib.mkDefault true;
    # Kanata remapper and fcitx5 input method; only have an effect on NixOS
    # (macOS uses Karabiner from the home keyboard group).
    keyboard.kanata.enable = lib.mkDefault true;
    keyboard.fcitx5.enable = lib.mkDefault true;
    security = {
      # Desktop authentication services and 1Password GUI; only have an effect on NixOS.
      keyring.enable = lib.mkDefault true;
      soteria.enable = lib.mkDefault true;
      onepasswordGui.enable = lib.mkDefault true;
      # Touch ID / Apple Watch sudo; only has an effect on Darwin.
      biometricSudo.enable = lib.mkDefault true;
    };
    # Homebrew casks; only has an effect on Darwin.
    homebrew.enable = lib.mkDefault true;
  };
}
