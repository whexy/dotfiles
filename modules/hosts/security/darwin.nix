{ config, lib, ... }:
let
  cfg = config.dotfiles.security;
in
{
  config = lib.mkMerge [
    {
      system.activationScripts.postActivation.text =
        let
          policy = "/Library/Application Support/ClaudeCode/managed-settings.d/50-dotfiles.json";
        in
        if cfg.agentPolicy.enable then
          ''
            mkdir -p '${builtins.dirOf policy}'
            if [ -e '${policy}' ] && [ ! -L '${policy}' ]; then
              echo 'Refusing to replace an unmanaged Claude policy: ${policy}' >&2
              exit 1
            fi
            ln -sfn ${../../home/agents/claude-code/settings.json} '${policy}'
          ''
        else
          ''
            if [ -L '${policy}' ]; then
              case "$(readlink '${policy}')" in
                /nix/store/*) rm '${policy}' ;;
              esac
            fi
          '';
    }

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
