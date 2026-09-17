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
    tailscale.port = lib.mkOption {
      type = lib.types.port;
      default = 41641;
      description = ''
        UDP port tailscaled binds for WireGuard.

        Direct connections need the outbound NAT to preserve this exact port.
        Linux masquerade does so only while no other tailscaled behind the same
        external IP wants the same one; on a collision it allocates a fresh port
        per flow, the STUN-discovered endpoint goes stale, and remote peers fall
        back to DERP. Hosts that share an external IP with other Tailscale nodes
        (Incus guests on one host) must give each node a distinct value.
      '';
    };
  };

  config = lib.mkIf cfg.tailscale.enable {
    services.tailscale = {
      enable = true;
      port = cfg.tailscale.port;
    };
  };
}
