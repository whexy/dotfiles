# Dev Darwin system configuration
{ pkgs, ... }:
{
  time.timeZone = "America/Chicago";
  programs.zsh.enable = true;
  environment.shells = with pkgs; [
    bash
    zsh
  ];

  # Enable Linux builder VM for building NixOS configurations on macOS
  nix.linux-builder = {
    enable = true;

    # VM resource allocation (conservative: 4 cores, 6 GB RAM)
    config = {
      virtualisation.cores = 4;
      virtualisation.memorySize = 6 * 1024; # 6 GB in MB
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
}
