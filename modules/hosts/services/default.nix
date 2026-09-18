# Services group: OpenSSH server, Caddy web server.
{ lib, ... }:
{
  options.dotfiles.services = {
    openssh = {
      enable = lib.mkEnableOption "the OpenSSH server";

      hardened = lib.mkEnableOption ''
        hardened OpenSSH settings for internet-facing hosts (no root login,
        no password authentication)'';

      trustedUserCAKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "ecdsa-sha2-nistp256 AAAA... ca@example.com" ];
        description = ''
          Public keys of certificate authorities trusted to sign user
          certificates for authentication (sshd TrustedUserCAKeys).'';
      };

      cloudflareAccess.enable = lib.mkEnableOption ''
        trusting the account-global Cloudflare Access (Gateway) SSH CA, so
        short-lived user certificates issued by Cloudflare Zero Trust are
        accepted for authentication'';
    };

    caddy.enable = lib.mkEnableOption "the Caddy web server with a user-managed /etc/caddy/Caddyfile";
  };
}
