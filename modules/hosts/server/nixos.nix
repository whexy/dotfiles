{ config, lib, ... }:
let
  cfg = config.dotfiles.server;
in
{
  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [
      22 # SSH
      80 # HTTP (Caddy)
      443 # HTTPS (Caddy)
    ];

    services = {
      resolved.enable = true;
      timesyncd.enable = true;

      # Logging
      journald.extraConfig = ''
        Storage=persistent
        SystemMaxUse=1G
        MaxRetentionSec=1month
      '';
    };
  };
}
