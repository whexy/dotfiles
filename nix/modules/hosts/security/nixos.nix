{ config, lib, ... }:
let
  cfg = config.dotfiles.security;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.passwordlessSudo.enable { security.sudo.wheelNeedsPassword = false; })

    (lib.mkIf cfg.onepassword.enable { programs._1password.enable = true; })

    (lib.mkIf cfg.fail2ban.enable { services.fail2ban.enable = true; })
  ];
}
