{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "neith";
    incusContainer = true;
    caps = [
      "base"
      "dev"
    ];
    modules = [ ./nvidia.nix ];
    overlays = [ flake.lib.overlays.docker-runc-lxc ];
  };

  # Incus guest on venus, sharing its public IP with k8s-4 and the other
  # personal VM there; each node needs its own WireGuard port so the host's
  # masquerade keeps preserving it. k8s-4 holds the default 41641.
  dotfiles = {
    system.autoUpgrade.enable = true;
    network.tailscale.port = 41642;
  };

  system.stateVersion = "26.05";
}
