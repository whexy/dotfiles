# Services Darwin configuration: Apple's built-in OpenSSH server (Remote Login).
{ config, lib, ... }:
{
  config = lib.mkIf config.dotfiles.services.openssh.enable {
    services.openssh.enable = true;
  };
}
