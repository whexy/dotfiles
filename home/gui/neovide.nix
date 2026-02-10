# Neovide - Neovim GUI client for connecting to remote neovim instances
{ pkgs, ... }:
{
  home.packages = [ pkgs.neovide ];

  xdg.configFile."neovide/config.toml".text = ''
    fork = false
    idle = true
    vsync = true

    [font]
    normal = ["FiraCode Nerd Font"]
    size = 16.0
  '';
}
