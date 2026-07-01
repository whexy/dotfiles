{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "desktop";
    caps = [
      "base"
      "dev"
      "gui"
    ];
    modules = [ flake.nixosModules.platform-desktop-vm-vmware ];
  };
}
