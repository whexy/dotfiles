{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles.agenticTooling.video.enable = true;
}
