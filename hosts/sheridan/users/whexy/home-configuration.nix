{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles.wm.darwin.windowManager = "aerospace";
  dotfiles.agents.t3code.server.enable = true;
}
