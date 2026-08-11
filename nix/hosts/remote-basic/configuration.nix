{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "remote-basic";
    caps = [ "base" ];
  };

  dotfiles.platform.qemuGuest.enable = true;
}
