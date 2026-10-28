{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles.agents.iphoneUse.enable = true;
}
