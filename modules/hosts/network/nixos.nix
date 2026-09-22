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
      services.tailscale = {
        enable = true;
        port = cfg.tailscale.port;
        # trustedInterfaces below covers traffic inside the tunnel, not the UDP
        # underlay tailscaled binds. Without this the nixos-fw input chain drops
        # unsolicited packets on that port, so a peer whose source port this
        # host cannot predict -- a Kubernetes pod behind flannel's `MASQUERADE
        # --random-fully` -- never establishes a direct path and stays on DERP.
        # Ordinary peers hide the problem because this host dials them first and
        # conntrack admits the reply.
        openFirewall = true;
      };
      networking.firewall.trustedInterfaces = [ "tailscale0" ];
    })
  ];
}
