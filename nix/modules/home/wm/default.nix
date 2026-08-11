# WM group: window managers (niri on Linux, aerospace on macOS).
{ inputs, lib, ... }:
{
  options.dotfiles.wm = {
    niri.enable = lib.mkEnableOption "the niri Wayland compositor";
    aerospace.enable = lib.mkEnableOption "aerospace tiling window manager (macOS)";
  };

  imports = [
    inputs.niri.homeModules.niri
    ./niri.nix
    ./aerospace.nix
  ];
}
