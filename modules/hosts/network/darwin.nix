{ config, lib, ... }:
let
  cfg = config.dotfiles.network;
in
{
  # tailscaled on macOS is launchd-managed and exposes no port setting, so
  # dotfiles.network.tailscale.port is deliberately unused here.
  config = lib.mkIf cfg.tailscale.enable { services.tailscale.enable = true; };
}
