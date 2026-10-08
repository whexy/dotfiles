# Services Darwin configuration: Apple's built-in OpenSSH server (Remote Login).
{ config, lib, ... }:
let
  cfg = config.dotfiles.services.openssh;
in
{
  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      # sshd keeps the first value it reads and loads drop-ins in name order,
      # so these hold only while Apple's 100-macos.conf leaves them unset.
      extraConfig = lib.mkIf cfg.hardened ''
        PermitRootLogin no
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        X11Forwarding no
      '';
    };
  };
}
