# Service NixOS system configuration
{ pkgs, ... }:
{
  time.timeZone = "America/Chicago";

  # Service essentials
  networking.networkmanager.enable = true;

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

  services.openssh.enable = true;
  services.tailscale.enable = true;

  # Docker (without gVisor)
  virtualisation.docker.enable = true;
}
