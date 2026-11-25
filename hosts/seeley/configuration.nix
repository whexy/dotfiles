{ flake, hostName, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    inherit hostName;
    caps = [
      "base"
      "dev"
      "gui"
    ];
    modules = [
      ./disk-config.nix
      ./hardware.nix
      ./nvidia.nix
    ];
  };

  services = {
    fstrim.enable = true;
    btrfs.autoScrub = {
      enable = true;
      fileSystems = [ "/" ];
    };
    # The wired port has a public campus address. SSH stays reachable over
    # tailscale0, which the firewall trusts.
    openssh.openFirewall = false;
    # Subnet router for the campus ranges, which the wired port reaches.
    # `tailscale set` keeps routes after the flag is dropped, so withdrawing
    # them takes an explicit empty `--advertise-routes=`.
    tailscale = {
      useRoutingFeatures = "server";
      extraSetFlags = [ "--advertise-routes=129.105.0.0/16,165.124.0.0/16" ];
    };
  };

  dotfiles = {
    system = {
      autoUpgrade.enable = true;
      fwupd.enable = true;
    };
    # A lab desktop that mostly serves as a headless server, on someone
    # else's power bill.
    power = {
      alwaysOn.enable = true;
      performance.enable = true;
    };
    # Published container ports would otherwise be open on the public
    # campus address.
    virtualization.docker.publishAddress = "127.0.0.1";
  };

  system.stateVersion = "26.05";
}
