# Service NixOS system configuration
{ ... }:
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
    # Users can edit /etc/caddy/Caddyfile and reload with: systemctl reload caddy
    configFile = "/etc/caddy/Caddyfile";
  };

  # Ensure Caddy directories and default config exist
  # Ordering: users (caddy user created) → caddy-config → caddy.service starts
  system.activationScripts.caddy-config = {
    deps = [ "users" ];
    text = ''
      mkdir -p /etc/caddy
      mkdir -p /var/www
      chown caddy:caddy /etc/caddy /var/www
      if [ ! -f /etc/caddy/Caddyfile ]; then
        cat > /etc/caddy/Caddyfile << 'CADDYEOF'
      # Caddy configuration file
      # Edit and reload with: systemctl reload caddy
      :80 {
          root * /var/www
          file_server browse
      }
      CADDYEOF
        chown caddy:caddy /etc/caddy/Caddyfile
        chmod 644 /etc/caddy/Caddyfile
      fi
    '';
  };

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

  # Export metrics
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 9100;
    enabledCollectors = [
      "systemd"
      "processes"
    ];
  };
}
