{
  config,
  flake,
  lib,
  ...
}:
let
  cfg = config.dotfiles.image.proxmox;
in
{
  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ flake.lib.overlays.lkl-bigmem ];
    system.stateVersion = "25.11";
    services.qemuGuest.enable = true;

    # Fallbacks overridden by nixos-generators' proxmox module.
    boot.loader.grub.device = lib.mkDefault "/dev/vda";
    fileSystems."/" = lib.mkDefault {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
  };
}
