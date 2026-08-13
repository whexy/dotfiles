# System group: timezone, auto-upgrade, developer documentation.
{ config, lib, ... }:
let
  cfg = config.dotfiles.system;
in
{
  options.dotfiles.system = {
    timezone.enable = lib.mkEnableOption "the dotfiles timezone (America/Chicago)";

    autoUpgrade = {
      enable = lib.mkEnableOption "daily auto-upgrade from github:whexy/dotfiles";

      configuration = lib.mkOption {
        type = lib.types.str;
        default = config.dotfiles.host.hostName;
        defaultText = "config.dotfiles.host.hostName";
        description = ''
          The nixosConfigurations.<name> (NixOS) or
          darwinConfigurations.<name> (Darwin) output of
          github:whexy/dotfiles to switch to. Override when the flake output
          name differs from the runtime hostname (e.g. moore has
          networking.hostName "moore-vm").
        '';
        example = "remote-dev";
      };
    };

    docs.enable = lib.mkEnableOption "developer documentation (man pages for syscalls & libc, sections 2 and 3)";
  };

  config = lib.mkIf cfg.timezone.enable { time.timeZone = "America/Chicago"; };
}
