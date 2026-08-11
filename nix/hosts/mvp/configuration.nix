{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "mvp";
    caps = [
      "base"
      "dev"
    ];
  };

  dotfiles.platform.qemuGuest.enable = true;
}
