{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "mudd";
    caps = [
      "base"
      "dev"
    ];
  };

  dotfiles = {
    system.autoUpgrade.enable = true;
    platform.qemuGuest.enable = true;
    services.openssh.cloudflareAccess.enable = true;
  };
}
