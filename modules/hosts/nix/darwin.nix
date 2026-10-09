{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.nix;
in
{
  config = lib.mkMerge [
    # Enable Linux builder VM for building NixOS configurations on macOS
    (lib.mkIf cfg.linuxBuilder.enable {
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
    })

    # launchd has no randomized delay, so the job draws the same 2h window
    # NixOS gets from its timer.
    (lib.mkIf cfg.gc.enable {
      launchd.daemons.nix-gc.command = lib.mkForce "${pkgs.writeShellScript "nix-gc" ''
        sleep $((RANDOM % 7200))
        exec ${config.nix.package}/bin/nix-collect-garbage ${config.nix.gc.options}
      ''}";
    })
  ];
}
