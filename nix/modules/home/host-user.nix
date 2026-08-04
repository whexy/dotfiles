{ inputs, osConfig, ... }:
{
  imports = inputs.self.lib.homeModulesForCaps osConfig.dotfiles.host.caps;

  # Keep the home-level tailscale flag in sync with the host.
  dotfiles.tailscale = osConfig.dotfiles.host.tailscale;
}
