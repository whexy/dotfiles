# Dev NixOS system configuration
{ pkgs, lib, ... }:
let
  host = pkgs.stdenv.hostPlatform.system;
  universe = [
    "x86_64-linux"
    "aarch64-linux"
    "riscv64-linux"
  ];
  emulated = lib.remove host universe;
in
{
  time.timeZone = "America/Chicago";
  programs.zsh.enable = true;
  security.sudo.wheelNeedsPassword = false;

  # Dev services
  networking.networkmanager.enable = true;
  services.openssh.enable = true;
  services.tailscale.enable = true;
  programs.nix-ld.enable = true;

  # Special Docker settings
  virtualisation.docker = {
    enable = true;
    # Update 2026-01-08: enabling gVisor runtime (company contract needs it)
    extraPackages = [ pkgs.gvisor ];
    daemon.settings = {
      runtimes = {
        runsc = {
          path = "${pkgs.gvisor}/bin/runsc";
        };
      };
    };
  };

  virtualisation.podman.enable = true;

  virtualisation.containers = {
    enable = true;
    registries.search = [ "docker.io" ];
  };

  # Emulate other platforms
  boot.binfmt.emulatedSystems = emulated;

  # Export metrics
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 9100;
    enabledCollectors = [
      "systemd"
      "processes"
    ];
  };
}
