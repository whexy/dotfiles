# Primary system user.
{ lib, ... }:
{
  options.dotfiles.user.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Configure the primary user from dotfiles.host.username.";
  };
}
