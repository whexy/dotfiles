{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles.agenticTooling.iphoneUse.enable = true;
  dotfiles.t3code.server.push.enable = true;

  home.stateVersion = "26.05";
}
