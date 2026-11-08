{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles.panel.linuxBar = "eww";

  home.stateVersion = "26.05";
}
