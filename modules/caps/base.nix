# base cap preset: very basic settings, all systems should have them.
#
# Caps are preset modules: importing one assigns dotfiles.* options with
# lib.mkDefault. Hosts override individual options with plain assignments.
{ flake, lib, ... }:
{
  dotfiles = {
    nix = {
      caches.enable = lib.mkDefault true;
      pinRegistry.enable = lib.mkDefault true;
      gc.enable = lib.mkDefault true;
    };
    shell.zsh.enable = lib.mkDefault true;
    # No-op on Darwin: the compat group only ships a nixos.nix.
    compat.envfs.enable = lib.mkDefault true;
  };

  nixpkgs.overlays = [
    flake.lib.overlays.unstable
    flake.lib.overlays.tailscale-security
    flake.lib.overlays.cloudflared-security
  ];
}
