# Wrapper to adapt standalone home-manager modules for NixOS/Darwin
# Usage: imports = [ (import ./wrapper.nix ./dev.nix) ];
homeModule:
{ ... }:
{
  home-manager.users.whexy = homeModule;
}
