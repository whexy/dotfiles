# Custom dotfiles home-manager options
{ lib, ... }:
{
  options.dotfiles = {
    tailscale = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether this host is connected to the tailnet (Tailscale).";
    };
  };
}
