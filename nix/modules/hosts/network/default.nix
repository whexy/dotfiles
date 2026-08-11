# Network group: NetworkManager basics, Tailscale.
{ config, lib, ... }:
let
  cfg = config.dotfiles.network;
in
{
  options.dotfiles.network = {
    basics.enable = lib.mkEnableOption "dotfiles networking basics (NetworkManager, nftables, trusted tailnet)";
    firewall.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the NixOS firewall.";
    };
    tailscale.enable = lib.mkEnableOption "Tailscale client";
  };

  config = lib.mkIf cfg.tailscale.enable {
    services.tailscale.enable = true;
  };
}
