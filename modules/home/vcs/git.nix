# Git configuration
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.vcs;
  signingKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIcI4E3boeSWD5+eb9K6Zotw7dxjjvHP60tBjoM0uYn";
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

      file.".git_allowed_signers" = lib.mkIf cfg.git.signing.enable {
        text = ''
          ${cfg.git.identity.email} ${signingKey}
        '';
      };
    };

    programs = {
      git = {
        enable = true;
        lfs.enable = true;

        # Agent scratch directories are per-machine and never belong to a repo.
        ignores = [
          ".pi/"
          ".claude/"
        ];

        signing = lib.mkIf cfg.git.signing.enable {
          key = signingKey;
          signByDefault = true;
        };

        settings = {
          user = { inherit (cfg.git.identity) name email; };

          gpg = lib.mkIf cfg.git.signing.enable {
            format = "ssh";
            ssh = {
              allowedSignersFile = "~/.git_allowed_signers";
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
        enableGitIntegration = true; # use delta as default git diff viewer/pager
        options = {
          line-numbers = true;
          side-by-side = true;
        };
      };

      jujutsu = {
        enable = true;
        settings = {
          user = { inherit (cfg.git.identity) name email; };
        };
      };
    };
  };
}
