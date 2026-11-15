{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles = {
    wm.darwin.windowManager = "aerospace";
    agenticTooling = {
      video.editing.enable = true;
      iphoneUse.enable = true;
    };
  };

  home.stateVersion = "26.05";
}
