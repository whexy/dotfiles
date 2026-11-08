# Command-line tools the zsh and nushell developer extras share. Each extras
# module sets only its own shell's integrations.
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
  config = lib.mkIf (cfg.zsh.devExtras || cfg.nushell.devExtras) {
    programs = {
      fzf.enable = true;
      zoxide.enable = true;

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

      # Runs direnv in a background daemon, in place of direnv's own hook.
      direnv-instant.enable = true;
    };
  };
}
