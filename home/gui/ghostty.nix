# Ghostty terminal configuration
{
  pkgs,
  lib,
  darwin,
  osConfig ? null,
  ...
}:
let
  ghostty-pkg = if darwin then pkgs.ghostty-bin else pkgs.ghostty;
  macbookScreen = osConfig.hardware.display.macbookScreen or false;

in
{
  programs.ghostty = {
    enable = true;
    package = ghostty-pkg;

    settings = {
      theme = "Gruvbox Dark";
      font-size = if macbookScreen then 16 else 14;
      font-family = "FiraCode Nerd Font";
      background-opacity = 0.90;
      background-blur = true;

      # Allow OSC 9 / OSC 777 sequences (emitted by tools like OpenCode over SSH)
      # to trigger desktop notifications in Ghostty.
      desktop-notifications = true;

      notify-on-command-finish = "unfocused";
      notify-on-command-finish-action = "bell,notify";

      keybind =
        lib.optionals (!darwin) [
          "ctrl+shift+zero=set_font_size:23"
          "ctrl+shift+r=reset"
          "ctrl+shift+arrow_down=jump_to_prompt:1"
          "ctrl+shift+arrow_up=jump_to_prompt:-1"
        ]
        ++ lib.optionals darwin [
          "alt+left=unbind"
          "alt+right=unbind"
          "cmd+shift+zero=set_font_size:23"
          "cmd+shift+r=reset"
          "cmd+shift+arrow_down=jump_to_prompt:1"
          "cmd+shift+arrow_up=jump_to_prompt:-1"
        ];
    }
    // {
      window-decoration = if darwin then "auto" else "none";
    };
  };
}
