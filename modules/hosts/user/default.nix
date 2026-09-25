# Primary system user.
{ lib, ... }:
{
  options.dotfiles.user = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Configure the primary user from dotfiles.host.username.";
    };
    # Only has an effect on NixOS; launchd agents already run for the
    # logged-in macOS user.
    linger = lib.mkEnableOption "the primary user's systemd user services running without a login session";
  };
}
