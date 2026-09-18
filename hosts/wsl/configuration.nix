{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "wsl";
    wsl = true;
    caps = [
      "base"
      "dev"
    ];
    modules = [
      ./hardware.nix
      ./nvidia.nix
    ];
    overlays = [
      flake.lib.overlays.op-wsl
      flake.lib.overlays.ssh-wsl
    ];
  };
}
