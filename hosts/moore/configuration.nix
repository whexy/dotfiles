{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "moore-vm";
    caps = [
      "base"
      "dev"
    ];
    modules = [ ./hardware.nix ];
  };
}
