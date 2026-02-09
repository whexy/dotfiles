# Service NixOS system configuration
{ pkgs, ... }:
{
  time.timeZone = "America/Chicago";

  # Service essentials
  networking.networkmanager.enable = true;
  services.tailscale.enable = true;
  services.resolved.enable = true;
  services.timesyncd.enable = true;

  # Caddy web server with user-managed Caddyfile
  services.caddy = {
    enable = true;
    # Point to user-managed configuration file
    # Users can edit /var/lib/caddy/Caddyfile and reload with: systemctl reload caddy
    configFile = "/var/lib/caddy/Caddyfile";
  };

  # Ensure Caddyfile exists before service starts
  systemd.services.caddy.preStart = ''
    if [ ! -f /var/lib/caddy/Caddyfile ]; then
      echo "# Caddy configuration file - Edit and reload with: systemctl reload caddy" > /var/lib/caddy/Caddyfile
      chown caddy:caddy /var/lib/caddy/Caddyfile
      chmod 644 /var/lib/caddy/Caddyfile
    fi
  '';

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
    };
  };

  # Docker (without gVisor)
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
    daemon.settings = {
      "log-driver" = "json-file";
      "log-opts" = {
        "max-size" = "50m";
        "max-file" = "3";
      };
    };
  };

  # Firewall configuration
  services.fail2ban.enable = true;
  networking.firewall.allowedTCPPorts = [
    22 # SSH
    80 # HTTP (Caddy)
    443 # HTTPS (Caddy)
  ];

  # Logging
  services.journald.extraConfig = ''
    Storage=persistent
    SystemMaxUse=1G
    MaxRetentionSec=1month
  '';
  services.prometheus.exporters.node.enable = true;
}
