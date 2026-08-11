{ config, lib, ... }:
let
  cfg = config.dotfiles.network;
in
{
  config = lib.mkMerge [
    {
      networking = {
        firewall.enable = cfg.firewall.enable;
        nftables.enable = cfg.nftables.enable;
      };
    }

    (lib.mkIf cfg.networkmanager.enable { networking.networkmanager.enable = true; })

    (lib.mkIf cfg.tailscale.enable {
      networking.firewall.trustedInterfaces = [ "tailscale0" ];
    })
  ];
}
