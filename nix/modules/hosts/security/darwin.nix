{ config, lib, ... }:
let
  cfg = config.dotfiles.security;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.onepassword.enable { programs._1password.enable = true; })

    # 1Password GUI via Homebrew cask (properly signed for browser integration)
    (lib.mkIf cfg.onepasswordGui.enable { homebrew.casks = [ "1password" ]; })

    (lib.mkIf cfg.biometricSudo.enable {
      security.pam.services.sudo_local = {
        touchIdAuth = true;
        watchIdAuth = true;
      };
    })
  ];
}
