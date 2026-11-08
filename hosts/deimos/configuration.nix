{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "deimos";
    incusContainer = true;
    caps = [
      "base"
      "dev"
    ];
  };

  # Incus guest on mars, sharing its public IP with k8s-5 and the other
  # personal VM there; each node needs its own WireGuard port so the host's
  # masquerade keeps preserving it. k8s-5 holds the default 41641.
  dotfiles = {
    system.autoUpgrade.enable = true;
    network.tailscale.port = 41642;
    platform.incusContainer.nvidia.enable = true;
  };

  system.stateVersion = "26.05";
}
