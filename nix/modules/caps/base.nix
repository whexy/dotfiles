# base cap preset: very basic settings, all systems should have them.
#
# Caps are preset modules: importing one assigns dotfiles.* options (plain
# priority). Hosts override individual options with lib.mkForce.
{ flake, lib, ... }:
{
  dotfiles = {
    nix.caches.enable = lib.mkDefault true;
    shell.zsh.enable = lib.mkDefault true;
    # No-op on Darwin: the compat group only ships a nixos.nix.
    compat.envfs.enable = lib.mkDefault true;
  };

  nixpkgs.overlays = [
    flake.lib.overlays.unstable
    flake.lib.overlays.tailscale-security
  ];
}
