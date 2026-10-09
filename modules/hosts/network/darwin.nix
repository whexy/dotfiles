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

    {
      launchd.daemons = lib.mapAttrs' (
        iface: mac:
        lib.nameValuePair "mac-address-${iface}" {
          # Cycling the network service restarts DHCP within that service, so
          # the lease uses the new address and System Settings and route
          # selection treat the interface as connected.
          #
          # The plist names a store path, so a nixpkgs update reloads the
          # daemon and reruns this mid-switch; an interface that already has
          # the address is left alone. The service is resolved before the
          # address changes so a retry never finds the address set but the
          # service not yet cycled.
          script = ''
            set -e
            service=$(/usr/sbin/networksetup -listnetworkserviceorder | /usr/bin/awk -v dev=${iface} '
              /^\([0-9*]+\) / { sub(/^\([0-9*]+\) /, ""); name = $0 }
              index($0, "Device: " dev ")") { print name; exit }')
            [ -n "$service" ]
            current=$(/sbin/ifconfig ${iface} | /usr/bin/awk '$1 == "ether" { print $2 }')
            [ "$current" != ${lib.toLower mac} ] || exit 0
            /sbin/ifconfig ${iface} ether ${mac}
            /usr/sbin/networksetup -setnetworkserviceenabled "$service" off
            /usr/sbin/networksetup -setnetworkserviceenabled "$service" on
          '';
          serviceConfig = {
            RunAtLoad = true;
            # Retry until the interface and its network service exist.
            KeepAlive.SuccessfulExit = false;
            StandardOutPath = "/var/log/mac-address-${iface}.log";
            StandardErrorPath = "/var/log/mac-address-${iface}.log";
          };
        }
      ) cfg.macAddresses;
    }

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
