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

  dotfiles = {
    system.autoUpgrade.enable = true;
    platform.qemuGuest.enable = true;
    services.openssh.cloudflareAccess.enable = true;
  };
}
