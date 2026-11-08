# Zellij terminal multiplexer configuration
{
  config,
  lib,
  ...
}:
let
  cfg = config.dotfiles.terminal;
in
{
  config = lib.mkIf cfg.zellij.enable {
    home.shellAliases = {
      zd = ''zellij attach --create "$(basename "$PWD")" options --default-cwd "$PWD"'';
    };

    programs.zellij = {
      enable = true;

      settings = {
        pane_frames = false;
        simplified_ui = true;
        default_mode = "locked";
        show_startup_tips = false;
        show_release_notes = false;
        session_serialization = false;
      };

      # Keybinds start from clear-defaults, so the file lists every binding.
      extraConfig = builtins.readFile ./zellij.kdl;
    };

    xdg.configFile."zellij/layouts/default.kdl".text = ''
      layout {
          pane size=1 borderless=true {
              plugin location="compact-bar"
          }
          pane
      }
    '';
  };
}
