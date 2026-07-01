{ inputs, osConfig, ... }:
{
  imports = inputs.self.lib.homeModulesForCaps osConfig.dotfiles.host.caps;
}
