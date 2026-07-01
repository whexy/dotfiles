{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "mvp";
    caps = [
      "base"
      "dev"
    ];
    modules = [ flake.nixosModules.platform-qemu-guest-uefi-disko ];
  };
}
