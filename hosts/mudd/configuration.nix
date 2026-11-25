{ flake, hostName, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    inherit hostName;
    caps = [
      "base"
      "dev"
    ];
  };

  # Subnet router for the lab LAN, which ens18 sits on. `tailscale set` keeps
  # routes after the flag is dropped, so withdrawing them takes an explicit
  # empty `--advertise-routes=`.
  services.tailscale = {
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-routes=192.168.2.0/24" ];
  };

  dotfiles = {
    system.autoUpgrade.enable = true;
    platform.qemuGuest.enable = true;
    services.openssh.cloudflareAccess.enable = true;
  };

  system.stateVersion = "25.11";
}
