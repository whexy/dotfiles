{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles = {
    wm.darwin.windowManager = "aerospace";
    agents = {
      video.enable = true;
      iphoneUse.enable = true;
    };
  };
}
