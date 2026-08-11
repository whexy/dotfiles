{ config, lib, ... }:
let
  cfg = config.dotfiles.security;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.onepassword.enable { programs._1password.enable = true; })

    (lib.mkIf cfg.biometricSudo.enable {
      security.pam.services.sudo_local = {
        touchIdAuth = true;
        watchIdAuth = true;
      };
    })
  ];
}
