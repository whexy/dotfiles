{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles = {
    panel.linuxBar = "eww";
    wm.niri.idleLock.enable = false;
  };

  home.stateVersion = "26.05";
}
