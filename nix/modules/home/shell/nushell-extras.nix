# Nushell developer extras (carapace, starship, zoxide, direnv, atuin, bat, eza)
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.shell;
in
{
  config = lib.mkIf cfg.nushell.devExtras {
    programs = {
      fzf.enable = true;
      zoxide.enable = true;

      carapace = {
        enable = true;
        enableNushellIntegration = true;
        enableZshIntegration = false;
        enableBashIntegration = false;
      };

      starship = {
        enable = true;
        enableNushellIntegration = true;
        enableZshIntegration = false;
        enableBashIntegration = false;
        settings = {
          add_newline = false;
        };
      };

      bat = {
        enable = true;
        extraPackages = with pkgs.bat-extras; [
          batdiff
          batman
          batgrep
          batwatch
        ];
      };

      eza = {
        enable = true;
        icons = "auto";
        extraOptions = [
          "--group-directories-first"
          "--header"
        ];
      };

      atuin = {
        enable = true;
        settings = {
          auto_sync = false;
          update_check = false;
          search_mode = "fuzzy";
          filter_mode = "global";
          enter_accept = true;
          style = "compact";
          inline_height = 30;
          store_failed = true;
        };
      };

      direnv = {
        enable = true;
        silent = true;
        nix-direnv.enable = true;
      };

      nushell = {
        shellAliases = {
          venv = "overlay use .venv/bin/activate.nu";
        };

        extraEnv = ''
          # Pin ssh socket to a fixed path
          # so tmux & zellij sessions can always get new sock without restart
          if ($env.SSH_AUTH_SOCK? != null and ($env.SSH_AUTH_SOCK | str starts-with "/tmp/")) {
            let fixed_sock = $"($env.HOME)/.ssh/ssh-agent.sock"
            try {
              ^ln -sf $env.SSH_AUTH_SOCK $fixed_sock
              $env.SSH_AUTH_SOCK = $fixed_sock
            }
          }
        '';

        extraConfig = ''
          # nix run nixpkgs# shortcut
          def nr [pkg: string, ...rest: string] {
            ^nix run $"nixpkgs#($pkg)" -- ...$rest
          }
        '';
      };
    };
  };
}
