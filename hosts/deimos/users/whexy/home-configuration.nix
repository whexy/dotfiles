{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles.agenticTooling.iphoneUse.enable = true;
}
