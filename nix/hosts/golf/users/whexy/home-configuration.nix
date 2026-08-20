{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles = {
    wm.darwin.windowManager = "paneru";
  };
}
