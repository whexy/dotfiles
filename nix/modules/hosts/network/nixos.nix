{ config, lib, ... }:
let
  cfg = config.dotfiles.network;
in
{
  config = lib.mkMerge [
    { networking.firewall.enable = cfg.firewall.enable; }

    (lib.mkIf cfg.basics.enable {
      networking = {
        networkmanager.enable = true;
        nftables.enable = true;
        firewall.trustedInterfaces = lib.mkIf cfg.tailscale.enable [ "tailscale0" ];
      };
    })
  ];
}
