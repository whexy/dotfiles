# gui cap preset: machines expected to have GUI environments.
{ lib, pkgs, ... }: {
  dotfiles = {
    desktop.enable = lib.mkDefault true;
    network.tailscale = {
      # The home t3-pair client finds T3 Code servers on the tailnet.
      enable = lib.mkDefault true;
      # The Rex app's server on the tailnet, on Darwin, where the home gui cap
      # installs the app. The dev cap covers NixOS.
      rex.enable = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (lib.mkDefault true);
    };
    fonts.enable = lib.mkDefault true;
    # The home browser group follows this; on Darwin it also installs the
    # Firefox Homebrew cask.
    browser.firefox.enable = lib.mkDefault true;
    # PipeWire audio stack; only has an effect on NixOS.
    audio.enable = lib.mkDefault true;
    # OBS Studio (with its virtual camera on NixOS), and the home streaming
    # tools.
    streaming.enable = lib.mkDefault true;
    keyboard = {
      # Kanata remapper; only has an effect on NixOS.
      kanata.enable = lib.mkDefault true;
      # The home keyboard group configures whichever of these the platform
      # has: fcitx5 on Linux, the Karabiner-Elements Homebrew cask on macOS.
      fcitx5.enable = lib.mkDefault (!pkgs.stdenv.hostPlatform.isDarwin);
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
      # swaylock PIN unlock, inert until `lock-pin set`; only has an effect on NixOS.
      lockPin.enable = lib.mkDefault true;
    };
    # Homebrew casks; only has an effect on Darwin.
    homebrew.enable = lib.mkDefault true;
  };
}
