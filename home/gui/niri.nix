# Niri Wayland compositor configuration (Linux)
{
  lib,
  darwin,
  inputs,
  ...
}:
{
  imports = lib.optionals (!darwin) [
    inputs.niri.homeModules.niri
  ];

  config = lib.mkIf (!darwin) {
    programs.niri.enable = true;
  };
}
