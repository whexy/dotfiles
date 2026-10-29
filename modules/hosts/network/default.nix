# Network group: firewall backend, NetworkManager, Tailscale.
{ lib, ... }:
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
    tailscale = {
      enable = lib.mkEnableOption ''
        Tailscale on this host. On WSL the Windows client owns the node, so
        only a CLI that drives it is installed
      '';
      userOperator = lib.mkEnableOption ''
        the primary user as Tailscale operator, so user services can change
        tailscaled state (e.g. `tailscale serve`) without root
      '';
      port = lib.mkOption {
        type = lib.types.port;
        default = 41641;
        description = ''
          UDP port tailscaled binds for WireGuard (Linux only; tailscaled on
          macOS is launchd-managed and takes no port).

          Direct connections need the outbound NAT to preserve this exact port.
          Linux masquerade does so only while no other tailscaled behind the same
          external IP wants the same one; on a collision it allocates a fresh port
          per flow, the STUN-discovered endpoint goes stale, and remote peers fall
          back to DERP. Hosts that share an external IP with other Tailscale nodes
          (Incus guests on one host) must give each node a distinct value.
        '';
      };
      rex = {
        enable = lib.mkEnableOption ''
          Rex for the primary user on the tailnet, at
          `https://<MagicDNS name>:<port>`. On macOS, Tailscale Serve forwards
          to the Rex app's server, which cannot tell callers apart, so every
          tailnet device the ACL lets reach this host gets a shell as that
          user. On NixOS, Rex's login server serves the route and admits only
          the tailnet owner's login, as that user (not on WSL)
        '';
        port = lib.mkOption {
          type = lib.types.port;
          default = 7297;
          description = ''
            HTTPS port of the Rex route. Rex clients try HTTPS on 7297 for a
            bare host name, so with this port a client adds the host by its
            MagicDNS name alone.
          '';
        };
      };
    };
    macAddresses = lib.mkOption {
      type = lib.types.attrsOf (lib.types.strMatching "([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}");
      default = { };
      example = {
        en0 = "90:09:d0:27:f6:fa";
      };
      description = ''
        MAC addresses assigned to interfaces at boot, for networks that lease
        only to a registered address (macOS only).
      '';
    };
    tailscaleOnly.interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "en0"
        "en1"
      ];
      description = ''
        Interfaces that drop inbound traffic unless it answers a connection
        this host opened, so services are reachable only over Tailscale (macOS
        only; NixOS hosts use the firewall). DHCP and IPv6 neighbor discovery
        still pass.
      '';
    };
  };
}
