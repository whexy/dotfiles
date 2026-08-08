# Daily auto-upgrade of a standalone Home Manager setup (non-NixOS hosts)
# from github:whexy/dotfiles, via a user-level systemd timer.
#
# Runs the same command documented for manual use, plus --refresh:
#   nh home switch github:whexy/dotfiles --refresh --no-nom -c <user>@<host> -b backup
#
# The <user>@<host> configuration name is deduced from the path of the
# home-configuration.nix that enabled this module (blueprint names the
# flake output after hosts/<host>/users/<user> but doesn't pass the host
# name into the module; the real machine hostname may differ).
#
# NOTE: on headless servers the user manager stops when you log out.
# Enable lingering once (manually) so the timer fires while logged out:
#   sudo loginctl enable-linger <user>
{
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.autoUpgrade;

  # Find the file that set dotfiles.autoUpgrade.enable = true and parse
  # "<user>@<host>" out of its path:
  #   hosts/<host>/users/<user>/home-configuration.nix
  enablingDef = lib.findFirst (def: (def.value or false) == true) null (
    options.dotfiles.autoUpgrade.enable.definitionsWithLocations or [ ]
  );
  pathMatch =
    if enablingDef != null then
      builtins.match ".*/hosts/([^/]+)/users/([^/]+)/home-configuration\\.nix" (toString enablingDef.file)
    else
      null;

  configuration =
    if cfg.configuration != null then
      cfg.configuration
    else if pathMatch != null then
      "${lib.elemAt pathMatch 1}@${lib.elemAt pathMatch 0}"
    else
      throw ''
        dotfiles.autoUpgrade: could not deduce the configuration name from
        the enabling file's path (expected hosts/<host>/users/<user>/home-configuration.nix).
        Set dotfiles.autoUpgrade.configuration explicitly.
      '';
in
{
  options.dotfiles.autoUpgrade = {
    enable = lib.mkEnableOption "daily auto-upgrade from github:whexy/dotfiles";

    configuration = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The homeConfigurations."<user>@<host>" output of github:whexy/dotfiles
        to switch to. When null, the name is deduced from the path of the
        home-configuration.nix that enabled this module
        (hosts/<host>/users/<user>). Set explicitly only if the file does
        not follow that layout.
      '';
      example = "wenxuan@mars";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.dotfiles-auto-upgrade = {
      Unit.Description = "Auto-upgrade Home Manager from github:whexy/dotfiles";
      Service = {
        Type = "oneshot";
        # nh shells out to nix; the user manager on generic-Linux hosts does
        # not inherit the login PATH.
        Environment = [
          "PATH=${
            lib.makeBinPath [
              pkgs.git
              config.nix.package
            ]
          }:/usr/local/bin:/usr/bin:/bin"
        ];
        ExecStart = toString [
          (lib.getExe pkgs.nh)
          "home"
          "switch"
          "github:whexy/dotfiles"
          "--refresh"
          "--no-nom"
          "-c"
          configuration
          "-b"
          "backup"
        ];
      };
    };

    systemd.user.timers.dotfiles-auto-upgrade = {
      Unit.Description = "Daily Home Manager auto-upgrade from github:whexy/dotfiles";
      Timer = {
        OnCalendar = "*-*-* 05:00:00";
        RandomizedDelaySec = "45min";
        # Catch up on missed runs (machine off at 05:00).
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
