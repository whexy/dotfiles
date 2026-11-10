{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles.agenticTooling.iphoneUse.enable = true;
  dotfiles.t3code.mesh.enable = true;

  home.stateVersion = "26.05";
}
