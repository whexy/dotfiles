# Dev NixOS system configuration
{ pkgs, ... }:
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

  virtualisation.podman = {
    enable = true;
    extraRuntimes = [ pkgs.gvisor ];
  };

  virtualisation.containers = {
    enable = true;
    registries.search = [ "docker.io" ];
  };
}
