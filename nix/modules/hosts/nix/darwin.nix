{ config, lib, ... }:
let
  cfg = config.dotfiles.nix;
in
{
  # Enable Linux builder VM for building NixOS configurations on macOS
  config = lib.mkIf cfg.linuxBuilder.enable {
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
  };
}
