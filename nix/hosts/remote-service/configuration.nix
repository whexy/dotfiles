{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "remote-service";
    caps = [
      "base"
      "service"
    ];
    modules = [ flake.nixosModules.image-proxmox ];
  };
}
