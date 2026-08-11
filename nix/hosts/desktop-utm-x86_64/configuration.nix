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
  };

  dotfiles.platform.desktopVm = {
    enable = true;
    backend = "utm";
  };
}
