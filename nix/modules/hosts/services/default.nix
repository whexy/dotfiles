# Services group: OpenSSH server, Caddy web server.
{ lib, ... }:
{
  options.dotfiles.services = {
    openssh = {
      enable = lib.mkEnableOption "the OpenSSH server";

      hardened = lib.mkEnableOption ''
        hardened OpenSSH settings for internet-facing hosts (no root login,
        no password authentication)'';
    };

    caddy.enable = lib.mkEnableOption "the Caddy web server with a user-managed /etc/caddy/Caddyfile";
  };
}
