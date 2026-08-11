# service cap preset: machines running internet-facing services.
{ lib, ... }: {
  dotfiles = {
    system.timezone.enable = lib.mkDefault true;
    network = {
      tailscale.enable = lib.mkDefault true;
      networkmanager.enable = lib.mkDefault true;
    };
    services = {
      openssh = {
        enable = lib.mkDefault true;
        hardened = lib.mkDefault true;
      };
      caddy.enable = lib.mkDefault true;
    };
    monitoring.nodeExporter.enable = lib.mkDefault true;
    security.fail2ban.enable = lib.mkDefault true;
    server.enable = lib.mkDefault true;
    virtualization.docker = {
      enable = lib.mkDefault true;
      serverHygiene = lib.mkDefault true;
    };
  };
}
