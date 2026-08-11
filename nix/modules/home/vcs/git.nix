# Git configuration
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.vcs;
in
{
  config = lib.mkIf cfg.git.enable {
    home = {
      packages = [ pkgs.gh ];

      # Disable system-level git config to prevent osxkeychain credential helper
      # on macOS from being automatically configured
      sessionVariables = {
        GIT_CONFIG_NOSYSTEM = "1";
      };

      file.".git_allowed_signers".text = ''
        whexy@outlook.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIcI4E3boeSWD5+eb9K6Zotw7dxjjvHP60tBjoM0uYn
      '';
    };

    programs = {
      git = {
        enable = true;
        lfs.enable = true;

        signing = {
          key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIcI4E3boeSWD5+eb9K6Zotw7dxjjvHP60tBjoM0uYn";
          signByDefault = true;
        };

        settings = {
          user = {
            name = "Wenxuan Shi";
            email = "whexy@outlook.com";
          };

          gpg = {
            format = "ssh";
            ssh = {
              allowedSignersFile = "~/.git_allowed_signers";
            }
            // lib.optionalAttrs pkgs.stdenv.isDarwin {
              program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
            };
          };

          credential = {
            "https://github.com" = {
              helper = "!${pkgs.gh}/bin/gh auth git-credential";
            };
            "https://gist.github.com" = {
              helper = "!${pkgs.gh}/bin/gh auth git-credential";
            };
          };
        };
      };

      delta = {
        enable = true;
        options = {
          line-numbers = true;
          side-by-side = true;
        };
      };

      jujutsu = {
        enable = true;
        settings = {
          user = {
            name = "Wenxuan Shi";
            email = "whexy@outlook.com";
          };
        };
      };
    };
  };
}
