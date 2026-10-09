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
      extraConfig = lib.mkMerge [
        # Drop a session whose client stopped answering, such as a suspended
        # laptop, after about 90 s rather than whenever TCP gives up. Its
        # forwarded agent socket goes with it, so the agent router falls back
        # to a live agent and requests relayed to it end.
        ''
          ClientAliveInterval 30
          ClientAliveCountMax 3
        ''
        (lib.mkIf cfg.hardened ''
          PermitRootLogin no
          PasswordAuthentication no
          KbdInteractiveAuthentication no
          X11Forwarding no
        '')
      ];
    };
  };
}
