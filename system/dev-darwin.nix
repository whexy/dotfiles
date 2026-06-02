# Dev Darwin system configuration
{ lib, ... }:
{
  nix = {
    optimise.automatic = true;
    settings.auto-optimise-store = true;
  };

  time.timeZone = "America/Chicago";
  services.tailscale.enable = true;

  # Enable Linux builder VM for building NixOS configurations on macOS
  nix.linux-builder = {
    enable = true;

    # VM resource allocation (4 cores, 6 GB RAM, 50 GB disk)
    config = {
      virtualisation = {
        cores = lib.mkForce 4;
        memorySize = lib.mkForce (6 * 1024); # 6 GB in MB
        diskSize = lib.mkForce (50 * 1024); # 50 GB in MB
      };
    };

    # Keep Nix store persistent for faster builds
    ephemeral = false;

    # Build machine settings
    maxJobs = 4;
    speedFactor = 1;
    supportedFeatures = [
      "kvm"
      "benchmark"
      "big-parallel"
    ];

    # Native Apple Silicon support only (fastest)
    systems = [ "aarch64-linux" ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 9100;
  };

  # Work around nix-darwin string comparison: the existing system user has
  # /private/var/… but the module defaults to /var/… (a symlink on macOS).
  users.users._prometheus-node-exporter.home = lib.mkForce "/private/var/lib/prometheus-node-exporter";
}
