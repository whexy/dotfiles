# base cap preset: very basic settings, all systems should have them.
#
# Caps are preset modules: importing one assigns dotfiles.* options (plain
# priority). Hosts override individual options with lib.mkForce.
{ flake, ... }:
{
  dotfiles = {
    nix.caches.enable = true;
    shell.zsh.enable = true;
    # No-op on Darwin: the compat group only ships a nixos.nix.
    compat.envfs.enable = true;
  };

  nixpkgs.overlays = [
    flake.lib.overlays.unstable
    flake.lib.overlays.tailscale-security
  ];
}
