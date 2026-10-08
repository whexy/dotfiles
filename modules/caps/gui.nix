# gui cap preset: machines expected to have GUI environments.
{ lib, pkgs, ... }: {
  dotfiles = {
    desktop.enable = lib.mkDefault true;
    # NixOS desktops serve VNC on the Tailscale interface and publish the
    # noVNC web client with `tailscale serve`.
    network.tailscale.enable = lib.mkDefault true;
    network.tailscale.userOperator = lib.mkDefault true;
    desktop.vnc.enable = lib.mkDefault true;
    fonts.enable = lib.mkDefault true;
    # Firefox Homebrew cask; only has an effect on Darwin (on NixOS,
    # Firefox is installed by the home browser group).
    browser.firefox.enable = lib.mkDefault true;
    # Chromium managed policies; Google Chrome Homebrew cask on Darwin.
    browser.chromium.enable = lib.mkDefault true;
    # PipeWire audio stack; only has an effect on NixOS.
    audio.enable = lib.mkDefault true;
    # OBS Studio with virtual camera; only has an effect on NixOS.
    streaming.enable = lib.mkDefault true;
    keyboard = {
      # Kanata remapper and fcitx5 input method; only have an effect on NixOS.
      kanata.enable = lib.mkDefault true;
      fcitx5.enable = lib.mkDefault true;
      # Karabiner-Elements ships as a Homebrew cask; its config comes from the
      # home keyboard group.
      karabiner.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isDarwin;
    };
    # Privileged helper for the Vicinae launcher's paste and snippet
    # expansion; only has an effect on NixOS.
    launcher.inputServer.enable = lib.mkDefault true;
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
