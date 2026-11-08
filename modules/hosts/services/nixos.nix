{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.services;

  # Access for infrastructure
  cloudflareAccessCAKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBPsy7z5TD/n3VeSnTshvO1Ks5B2Mz0pJGl3pwF1SksQh/cFec1S6tpY5EDO4XylkD1pA+WjSXZzxw9EEirr68NQ= open-ssh-ca@cloudflareaccess.org";
  # Access for SSH Tunnel
  cloudflareTunnelCAKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBLodc6lArLuwV6cVhG8IgHGn0l17mIwidCpAigp5KpK7E0Kldikr3BgcpBlz9gL+beFNb40wu8odBHqECQEmnJk= open-ssh-ca@cloudflareaccess.org";

  trustedUserCAKeys =
    cfg.openssh.trustedUserCAKeys
    ++ lib.optionals cfg.openssh.cloudflareAccess.enable [
      cloudflareAccessCAKey
      cloudflareTunnelCAKey
    ];
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.openssh.enable {
      services.openssh = {
        enable = true;
        settings = lib.mkMerge [
          # Drop a session whose client stopped answering, such as a suspended
          # laptop, after about 90 s rather than whenever TCP gives up. Its
          # forwarded agent socket goes with it, so the agent router falls back
          # to a live agent and requests relayed to it end.
          {
            ClientAliveInterval = 30;
            ClientAliveCountMax = 3;
          }
          (lib.mkIf cfg.openssh.hardened {
            PermitRootLogin = "no";
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
            X11Forwarding = false;
          })
          # Cloudflare's browser-rendered SSH client only offers non-ETM MACs
          # (hmac-sha2-256, hmac-sha2-512), which nixpkgs' curated ETM-only
          # default list rejects. Allow them alongside the hardened defaults.
          (lib.mkIf cfg.openssh.cloudflareAccess.enable {
            Macs = [
              "hmac-sha2-512-etm@openssh.com"
              "hmac-sha2-256-etm@openssh.com"
              "umac-128-etm@openssh.com"
              "hmac-sha2-512"
              "hmac-sha2-256"
            ];
          })
        ];
        extraConfig = lib.mkIf (trustedUserCAKeys != [ ]) ''
          TrustedUserCAKeys ${pkgs.writeText "trusted-user-ca-keys" (lib.concatLines trustedUserCAKeys)}
        '';
      };
    })
  ];
}
