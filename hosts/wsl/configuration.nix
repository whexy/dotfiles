{ flake, hostName, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    inherit hostName;
    wsl = true;
    caps = [
      "base"
      "dev"
    ];
  };

  dotfiles = {
    system.autoUpgrade.enable = true;
    platform.wsl.nvidia.enable = true;
  };

  system.stateVersion = "25.11";
}
