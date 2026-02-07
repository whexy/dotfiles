# Niri Wayland compositor configuration (Linux)
{
  lib,
  darwin,
  inputs,
  ...
}:
if darwin then
  { }
else
  {
    imports = [
      inputs.niri.homeModules.niri
    ];

    programs.niri.enable = true;
  }
