# service cap preset: machines running internet-facing services.
_: {
  dotfiles = {
    system.timezone.enable = true;
    network = {
      tailscale.enable = true;
      networkmanager.enable = true;
    };
    services = {
      openssh = {
        enable = true;
        hardened = true;
      };
      caddy.enable = true;
    };
    monitoring.nodeExporter.enable = true;
    security.fail2ban.enable = true;
    server.enable = true;
    virtualization.docker = {
      enable = true;
      serverHygiene = true;
    };
  };
}
