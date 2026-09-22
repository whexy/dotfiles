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
          auto_sync = true;
          sync_address = "https://atuin.at-basking.ts.net";
          update_check = false;
          search_mode = "fuzzy";
          search_mode_shell_up_key_binding = "prefix";
          filter_mode = "global";
          filter_mode_shell_up_key_binding = "workspace";
          workspaces = true;
          enter_accept = false;
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
