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

    # Niri settings
    programs.niri.settings = {
      binds = {
        # Use wezterm as the default terminal
        "Mod+T".action.spawn = "wezterm";
      };
    };
  }
