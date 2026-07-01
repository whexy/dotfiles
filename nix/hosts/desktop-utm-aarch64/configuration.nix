{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "aarch64-linux";
    hostName = "desktop";
    caps = [
      "base"
      "dev"
      "gui"
    ];
    modules = [ flake.nixosModules.platform-desktop-vm-utm ];
  };
}
