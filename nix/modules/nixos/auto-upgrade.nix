# Daily auto-upgrade of this host from github:whexy/dotfiles.
#
# Wraps the built-in NixOS auto-upgrade (nixos-upgrade.service/.timer),
# which runs the equivalent of:
#   nixos-rebuild switch --refresh --flake github:whexy/dotfiles#<configuration>
{ config, lib, ... }:
let
  cfg = config.dotfiles.autoUpgrade;
in
{
  options.dotfiles.autoUpgrade = {
    enable = lib.mkEnableOption "daily auto-upgrade from github:whexy/dotfiles";

    configuration = lib.mkOption {
      type = lib.types.str;
      default = config.dotfiles.host.hostName;
      defaultText = "config.dotfiles.host.hostName";
      description = ''
        The nixosConfigurations.<name> output of github:whexy/dotfiles to
        switch to. Override when the flake output name differs from the
        runtime hostname (e.g. moore has networking.hostName "moore-vm").
      '';
      example = "remote-dev";
    };
  };

  config = lib.mkIf cfg.enable {
    system.autoUpgrade = {
      enable = true;
      flake = "github:whexy/dotfiles#${cfg.configuration}";
      dates = "04:00";
      randomizedDelaySec = "45min";
      # Catch up on missed runs (laptops asleep / machines off at 04:00).
      persistent = true;
    };
  };
}
