{ config, lib, ... }:
let
  cfg = config.dotfiles.security;
  username = config.dotfiles.host.username;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.passwordlessSudo.enable { security.sudo.wheelNeedsPassword = false; })

    (lib.mkIf cfg.onepassword.enable { programs._1password.enable = true; })

    (lib.mkIf cfg.onepasswordGui.enable {
      programs._1password-gui = {
        enable = true;
        polkitPolicyOwners = [ username ];
      };
    })

    # GNOME Keyring: implements the Secret portal for apps that need credentials
    (lib.mkIf cfg.keyring.enable { services.gnome.gnome-keyring.enable = true; })

    (lib.mkIf cfg.fail2ban.enable { services.fail2ban.enable = true; })
  ];
}
