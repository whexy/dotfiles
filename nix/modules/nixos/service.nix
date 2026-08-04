# Service NixOS system configuration
{ config, ... }:
{
  time.timeZone = "America/Chicago";

  networking = {
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [
      22 # SSH
      80 # HTTP (Caddy)
      443 # HTTPS (Caddy)
    ];
  };

  services = {
    # Service essentials
    tailscale.enable = config.dotfiles.host.tailscale;
    resolved.enable = true;
    timesyncd.enable = true;
    fail2ban.enable = true;

    # Caddy web server with user-managed Caddyfile
    caddy = {
      enable = true;
      # Point to user-managed configuration file
      # Users can edit /etc/caddy/Caddyfile and reload with: systemctl reload caddy
      configFile = "/etc/caddy/Caddyfile";
    };

    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        X11Forwarding = false;
      };
    };

    # Logging
    journald.extraConfig = ''
      Storage=persistent
      SystemMaxUse=1G
      MaxRetentionSec=1month
    '';

    # Export metrics
    prometheus.exporters.node = {
      enable = true;
      listenAddress = "0.0.0.0";
      port = 9100;
      enabledCollectors = [
        "systemd"
        "processes"
      ];
    };
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
}
