{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles.agenticTooling.video.editing.enable = true;

  home.stateVersion = "26.05";
}
