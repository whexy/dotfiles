{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "remote-basic";
    caps = [ "base" ];
    modules = [ flake.nixosModules.platform-qemu-guest-uefi-disko ];
  };
}
