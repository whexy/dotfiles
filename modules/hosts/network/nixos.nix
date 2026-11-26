{
  config,
  inputs,
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
  imports = [ inputs.rex.nixosModules.default ];

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
      };
      networking.firewall.trustedInterfaces = [ "tailscale0" ];
    })

    # Set either way, so turning the option off stops a server tailscaled
    # would otherwise keep across restarts.
    (lib.mkIf (cfg.tailscale.enable && !wsl) {
      services.tailscale.extraSetFlags = [ "--ssh=${lib.boolToString cfg.tailscale.ssh.enable}" ];
    })

    (lib.mkIf (cfg.tailscale.enable && cfg.tailscale.userOperator && !wsl) {
      services.tailscale.extraSetFlags = [ "--operator=${config.dotfiles.host.username}" ];
    })

    (lib.mkIf (cfg.tailscale.enable && wsl) {
      environment.systemPackages = [ pkgs.tailscale-wsl ];

      dotfiles.network.wslServe = {
        ssh = lib.mkIf config.services.openssh.enable {
          port = 22;
          target = "127.0.0.1:${toString (lib.head config.services.openssh.ports)}";
        };
        # The primary user's personal server listens here
        # (modules/home/terminal/rex.nix).
        rex = lib.mkIf cfg.tailscale.rex.enable {
          inherit (cfg.tailscale.rex) port;
          https = true;
          target = "127.0.0.1:${toString cfg.tailscale.rex.port}";
        };
      };
    })

    # A user service, because only the user's manager has WSL's interop, which
    # runs tailscale.exe. The routes are left in place on stop: removing port
    # 22's would cut the ssh session that switched this host.
    (lib.mkIf (cfg.tailscale.enable && wsl && cfg.wslServe != { }) {
      systemd.user.services.tailscale-wsl-serve = {
        description = "Tailscale Serve routes from the Windows node to WSL";
        wantedBy = [ "default.target" ];
        unitConfig.ConditionUser = config.dotfiles.host.username;
        path = [
          pkgs.tailscale-wsl
          pkgs.jq
          pkgs.coreutils
        ];
        serviceConfig = {
          ExecStart = pkgs.writeShellScript "tailscale-wsl-serve" ''
            while true; do
              if status=$(timeout -k 2 10 tailscale status --json) &&
                name=$(jq -er 'select(.BackendState == "Running") | .Self.DNSName | select(type == "string" and length > 0) | rtrimstr(".")' <<<"$status") &&
                serve=$(timeout -k 2 10 tailscale serve status --json); then
                ${lib.concatMapStrings (
                  route:
                  let
                    port = toString route.port;
                  in
                  if route.https then
                    ''
                      jq -e --arg host "$name:${port}" '.Web[$host].Handlers["/"].Proxy == "http://${route.target}"' <<<"$serve" >/dev/null ||
                        timeout -k 2 10 tailscale serve --bg --https=${port} http://${route.target} >/dev/null ||
                        echo 'tailscale-wsl-serve: could not route port ${port}; retrying' >&2
                    ''
                  else
                    ''
                      jq -e '.TCP["${port}"].TCPForward == "${route.target}"' <<<"$serve" >/dev/null ||
                        timeout -k 2 10 tailscale serve --bg --tcp=${port} tcp://${route.target} >/dev/null ||
                        echo 'tailscale-wsl-serve: could not route port ${port}; retrying' >&2
                    ''
                ) (lib.attrValues cfg.wslServe)}
              fi
              sleep 30
            done
          '';
          Restart = "always";
          RestartSec = 10;
        };
      };
    })

    # The login server learns each caller's Tailscale login from tailscaled,
    # which the Windows client on WSL cannot provide.
    (lib.mkIf (cfg.tailscale.enable && cfg.tailscale.rex.enable && !wsl) {
      services.rex.loginServer = {
        enable = true;
        accounts.${config.dotfiles.host.username}.principals = [ "tailscale:whexy@github" ];
        tailscaleServe = {
          enable = true;
          httpsPort = cfg.tailscale.rex.port;
        };
      };
    })
  ];
}
