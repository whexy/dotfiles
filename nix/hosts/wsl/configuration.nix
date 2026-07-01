{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "nixos-wsl";
    wsl = true;
    caps = [
      "base"
      "dev"
    ];
    modules = [ ./hardware.nix ];
    overlays = [
      flake.lib.overlays.op-wsl
      flake.lib.overlays.ssh-wsl
    ];
  };
}
