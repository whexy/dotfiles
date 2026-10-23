{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles = {
    wm.darwin.windowManager = "aerospace";
    agents.spark = {
      enable = true;
      server.enable = true;
    };
  };
}
