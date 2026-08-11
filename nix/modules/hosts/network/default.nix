# Network group: firewall backend, NetworkManager, Tailscale.
{ config, lib, ... }:
let
  cfg = config.dotfiles.network;
in
{
  options.dotfiles.network = {
    firewall.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the NixOS firewall.";
    };
    nftables.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use nftables as the firewall backend (required by Incus).";
    };
    networkmanager.enable = lib.mkEnableOption "NetworkManager";
    tailscale.enable = lib.mkEnableOption "Tailscale client";
  };

  config = lib.mkIf cfg.tailscale.enable {
    services.tailscale.enable = true;
  };
}
