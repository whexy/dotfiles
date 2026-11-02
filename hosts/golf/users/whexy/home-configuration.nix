{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles = {
    wm.darwin.windowManager = "aerospace";
    agenticTooling = {
      video.enable = true;
      iphoneUse.enable = true;
    };
  };
}
