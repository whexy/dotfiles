{ lib, ... }:
{
  options.dotfiles.desktop = {
    enable = lib.mkEnableOption "desktop environment (Wayland/niri on NixOS, macOS settings on Darwin)";
  };
}
