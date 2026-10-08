{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles.panel.linuxBar = "eww";
}
