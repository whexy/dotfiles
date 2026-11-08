{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  home.stateVersion = "26.05";
}
