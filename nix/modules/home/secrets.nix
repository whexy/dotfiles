{ config, ... }:
{
  age.identityPaths = [ "${config.home.homeDirectory}/.config/agenix/key.txt" ];
}
