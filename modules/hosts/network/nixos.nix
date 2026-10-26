{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.network;
  # WSL shares the Windows network stack, so the Windows client owns the
  # tailnet node; a Linux tailscaled there would register a second one.
  inherit (config.dotfiles.host) wsl;
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

    (lib.mkIf (cfg.tailscale.enable && !wsl) {
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
        # The kill switch below makes tailscaled reject every `tailscale set`
        # while the stored prefs still ask for the SSH server.
        extraSetFlags = [ "--ssh=false" ];
      };
      # Tailscale SSH has unpatched privilege-escalation findings
      # (https://tailscale.com/ssh-investigation-update), so OpenSSH serves
      # port 22 on tailscale0 until a fixed tailscale ships.
      systemd.services.tailscaled.environment.TS_DISABLE_SSH_SERVER = "1";
      networking.firewall.trustedInterfaces = [ "tailscale0" ];
    })

    (lib.mkIf (cfg.tailscale.enable && cfg.tailscale.userOperator && !wsl) {
      services.tailscale.extraSetFlags = [ "--operator=${config.dotfiles.host.username}" ];
    })

    (lib.mkIf (cfg.tailscale.enable && wsl) {
      environment.systemPackages = [ pkgs.tailscale-wsl ];
    })
  ];
}
