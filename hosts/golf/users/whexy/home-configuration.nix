{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles = {
    wm.darwin.windowManager = "aerospace";
    tooling.appStoreConnect.apiKey.enable = true;
    agents = {
      video.enable = true;
      iphoneUse.enable = true;
    };
  };
}
