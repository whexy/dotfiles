{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "phobos";
    caps = [
      "base"
      "dev"
    ];
    modules = [ ./disk-config.nix ];
  };

  # Incus guest on mars, sharing its public IP with k8s-5 and the other
  # personal VM there; each node needs its own WireGuard port so the host's
  # masquerade keeps preserving it. k8s-5 holds the default 41641.
  dotfiles = {
    system.autoUpgrade.enable = true;
    network.tailscale.port = 41643;
    platform.incusVm = {
      enable = true;
      # The hypervisor is not fully trusted. Disable every agent API that can
      # execute commands or read guest files (which would expose agenix
      # secrets under /run/agenix), and interface state (VM IPs in incus list).
      agent.features = {
        exec = false;
        files = false;
        state = false;
      };
    };
  };

  system.stateVersion = "26.05";
}
