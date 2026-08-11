{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "aarch64-linux";
    hostName = "mba-nixos";
    caps = [
      "base"
      "dev"
      "gui"
    ];
    modules = [ ./hardware.nix ];
  };

  dotfiles.platform.desktopVm = {
    enable = true;
    backend = "vmware";
  };
}
