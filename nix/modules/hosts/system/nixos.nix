{ config, lib, ... }:
let
  cfg = config.dotfiles.system;
in
{
  config = lib.mkMerge [
    # Daily auto-upgrade of this host from github:whexy/dotfiles.
    #
    # Wraps the built-in NixOS auto-upgrade (nixos-upgrade.service/.timer),
    # which runs the equivalent of:
    #   nixos-rebuild switch --refresh --flake github:whexy/dotfiles#<configuration>
    (lib.mkIf cfg.autoUpgrade.enable {
      system.autoUpgrade = {
        enable = true;
        flake = "github:whexy/dotfiles#${cfg.autoUpgrade.configuration}";
        dates = "04:00";
        randomizedDelaySec = "45min";
        # Catch up on missed runs (laptops asleep / machines off at 04:00).
        persistent = true;
      };
    })

    (lib.mkIf cfg.docs.enable { documentation.dev.enable = true; })
  ];
}
