{ config, lib, ... }:
let
  cfg = config.dotfiles.services;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.openssh.enable {
      services.openssh = {
        enable = true;
        settings = lib.mkIf cfg.openssh.hardened {
          PermitRootLogin = "no";
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          X11Forwarding = false;
        };
      };
    })

    (lib.mkIf cfg.caddy.enable {
      # Caddy web server with user-managed Caddyfile.
      # Users can edit /etc/caddy/Caddyfile and reload with: systemctl reload caddy
      services.caddy = {
        enable = true;
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
    })
  ];
}
