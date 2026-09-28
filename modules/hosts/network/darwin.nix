{ config, lib, ... }:
let
  cfg = config.dotfiles.network;
in
{
  # tailscaled on macOS is launchd-managed and exposes no port setting, so
  # dotfiles.network.tailscale.port is deliberately unused here.
  config = lib.mkIf cfg.tailscale.enable (
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
  );
}
