{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.network;

  # Apple's /etc/pf.conf already evaluates `anchor "com.apple/*"`, so rules
  # loaded beneath it apply without editing pf.conf, which macOS updates
  # restore.
  tailscaleOnlyAnchor = "com.apple/090.dotfiles.tailscale-only";
  tailscaleOnlyRules = pkgs.writeText "tailscale-only.pf.conf" ''
    ifs = "{ ${lib.concatStringsSep " " cfg.tailscaleOnly.interfaces} }"
    # Peers behind a smaller MTU (Kubernetes pods) fragment large WireGuard
    # packets, and later fragments carry no ports to match state with.
    scrub in on $ifs all fragment reassemble
    pass out on $ifs all keep state
    pass in quick on $ifs inet proto udp from any port 67 to any port 68
    pass in quick on $ifs inet6 proto udp from any port 547 to any port 546
    pass in quick on $ifs inet6 proto icmp6 all
    block in quick on $ifs all
  '';
in
{
  config = lib.mkMerge [
    # tailscaled on macOS is launchd-managed and exposes no port setting, so
    # dotfiles.network.tailscale.port is deliberately unused here.
    (lib.mkIf cfg.tailscale.enable (
      lib.mkMerge [
        {
          services.tailscale.enable = true;
          # nix-darwin links /etc/resolver/ts.net into /etc/static, but tailscaled
          # writes /etc/resolver through os.Root, which rejects symlinks leaving
          # the directory and so fails the whole DNS configuration. tailscaled
          # writes the same MagicDNS resolver file itself.
          environment.etc."resolver/ts.net".enable = false;
        }

        # nix-darwin has no counterpart to NixOS's extraSetFlags. tailscaled may
        # not be up yet on first activation; the next one applies it.
        (lib.mkIf cfg.tailscale.userOperator {
          system.activationScripts.postActivation.text = ''
            ${lib.getExe' config.services.tailscale.package "tailscale"} set --operator=${config.dotfiles.host.username} \
              || echo "warning: could not make ${config.dotfiles.host.username} the Tailscale operator" >&2
          '';
        })
      ]
    ))

    # tailscaled picks its own UDP port here, so unsolicited packets to it are
    # dropped too: peers this host dials first still connect directly, others
    # fall back to DERP.
    (lib.mkIf (cfg.tailscaleOnly.interfaces != [ ]) {
      launchd.daemons.pf-tailscale-only = {
        script = ''
          /sbin/pfctl -a ${tailscaleOnlyAnchor} -f ${tailscaleOnlyRules}
          /sbin/pfctl -E
        '';
        serviceConfig = {
          RunAtLoad = true;
          StandardOutPath = "/var/log/pf-tailscale-only.log";
          StandardErrorPath = "/var/log/pf-tailscale-only.log";
        };
      };
    })
  ];
}
